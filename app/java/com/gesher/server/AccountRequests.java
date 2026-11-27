/* Copyright (C) 2026 The Gesher Authors; SPDX-License-Identifier: Apache-2.0 */
package com.gesher.server;

import android.accounts.AccountManager;
import android.accounts.IAccountManagerResponse;
import android.os.Bundle;
import android.os.IBinder;
import android.os.RemoteException;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.RunnableScheduledFuture;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.ScheduledThreadPoolExecutor;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.BooleanSupplier;
import java.util.function.LongSupplier;

/**
 * Admission for asynchronous AccountManager authenticator operations. A ticket
 * belongs to real work, interactive sessions and callback execution together;
 * delivering a timeout does not recycle a still-running authenticator call.
 *
 * <p>The limits count owners and callback envelopes, not arbitrary Bundle bytes or
 * process RSS. Durable account-change notifications and opaque saved sessions have
 * different owners and are deliberately not dispatched through these lanes.
 */
final class AccountRequests {
    static final int MAX_REQUESTS = 256;
    static final int MAX_PER_CALLER = 64;
    static final int MAX_WORKERS = 32;
    static final int MAX_CALLBACK_WORKERS = 4;
    static final int MAX_RESULTS = 8;
    static final int MAX_DEPENDENCIES = 32;
    static final long TIMEOUT_MILLIS = TimeUnit.MINUTES.toMillis(15);
    static final long IDLE_SECONDS = 60;
    private static final long RETRY_MILLIS = 1000;

    interface Preparation { Runnable prepare(IAccountManagerResponse response); }
    interface Lease extends AutoCloseable { @Override void close(); }

    private final Object lock = new Object();
    private final LongSupplier uptime;
    private final LinkedHashSet<Request> requests = new LinkedHashSet<>();
    private final Map<String, Integer> callers = new HashMap<>();
    private final ThreadLocal<Request> current = new ThreadLocal<>();
    private final ThreadPoolExecutor workers = pool(MAX_WORKERS, "accounts-call");
    private final ThreadPoolExecutor callbacks = pool(MAX_CALLBACK_WORKERS, "accounts-response");
    private final Timers timers = new Timers();

    AccountRequests(LongSupplier uptime) { this.uptime = uptime; }

    private static ThreadFactory threads(String name) {
        AtomicInteger sequence = new AtomicInteger();
        return action -> {
            Thread thread = new Thread(action, name + "-" + sequence.incrementAndGet());
            thread.setDaemon(true);
            return thread;
        };
    }

    private static ThreadPoolExecutor pool(int count, String name) {
        ThreadPoolExecutor pool = new ThreadPoolExecutor(count, count, IDLE_SECONDS,
                TimeUnit.SECONDS, new ArrayBlockingQueue<>(MAX_REQUESTS), threads(name));
        pool.allowCoreThreadTimeOut(true);
        return pool;
    }

    private static final class Timer implements Runnable {
        final Runnable action;
        RunnableScheduledFuture<?> future;
        Timer(Runnable action) { this.action = action; }
        @Override public void run() { action.run(); }
    }

    private static final class Timers extends ScheduledThreadPoolExecutor {
        Timers() {
            super(1, threads("accounts-admission-timeout"));
            setRemoveOnCancelPolicy(true);
            setKeepAliveTime(IDLE_SECONDS, TimeUnit.SECONDS);
            allowCoreThreadTimeOut(true);
        }
        @Override protected <V> RunnableScheduledFuture<V> decorateTask(
                Runnable action, RunnableScheduledFuture<V> future) {
            if (action instanceof Timer) ((Timer) action).future = future;
            return future;
        }
    }

    private ScheduledFuture<?> schedule(Runnable action, long delayMillis) {
        Timer timer = new Timer(action);
        try {
            return timers.schedule(timer, Math.max(0, delayMillis), TimeUnit.MILLISECONDS);
        } catch (RuntimeException | Error unavailable) {
            // ScheduledThreadPoolExecutor inserts its future before starting its
            // first thread. Roll back that future even if Thread.start throws.
            if (timer.future != null) {
                timer.future.cancel(false);
                timers.remove(timer.future);
            }
            throw unavailable;
        }
    }

    private static void error(IAccountManagerResponse response, int code, String message) {
        if (response == null) return;
        try { response.onError(code, message); }
        catch (RemoteException ignored) { }
    }

    /** Caller identity is captured and authorized before this method is entered. */
    void execute(String caller, IAccountManagerResponse response, BooleanSupplier valid,
            Preparation preparation) {
        Request request = null;
        synchronized (lock) {
            int count = callers.getOrDefault(caller, 0);
            if (requests.size() < MAX_REQUESTS && count < MAX_PER_CALLER) {
                request = new Request(caller, response, valid);
                requests.add(request);
                callers.put(caller, count + 1);
            }
        }
        if (request == null) {
            // Rejection executes on the API caller. It creates no retained input,
            // internal worker or callback queue entry, like existing immediate
            // authenticator-unavailable errors at this public API boundary.
            error(response, AccountManager.ERROR_CODE_REMOTE_EXCEPTION, "Account service busy");
            return;
        }
        Request accepted = request;
        boolean timerReady = false;
        try {
            synchronized (lock) {
                accepted.expiry = schedule(accepted::expire,
                        accepted.deadline - uptime.getAsLong());
                timerReady = true;
            }
            accepted.watch();
            boolean alive;
            synchronized (lock) { alive = !accepted.terminal; }
            // Admission precedes options copies and one-shot session consumption.
            Runnable operation = alive ? preparation.prepare(accepted.response) : null;
            synchronized (lock) {
                accepted.preparing = false;
                if (!accepted.terminal && uptime.getAsLong() >= accepted.deadline) {
                    accepted.failLocked(AccountManager.ERROR_CODE_REMOTE_EXCEPTION, "timeout");
                }
                if (!accepted.terminal) {
                    accepted.operation = operation;
                    accepted.workOwned = true;
                    try {
                        workers.execute(accepted);
                    } catch (RuntimeException | Error unavailable) {
                        workers.remove(accepted);
                        accepted.workOwned = false;
                        accepted.operation = null;
                        accepted.failLocked(AccountManager.ERROR_CODE_REMOTE_EXCEPTION,
                                "Account worker unavailable");
                    }
                }
                accepted.dispatchLocked();
            }
        } catch (RuntimeException | Error invalid) {
            if (!timerReady) {
                // No request input or Binder link exists yet. Failure to establish
                // the deadline means admission never became externally active.
                synchronized (lock) { accepted.removeLocked(); }
                error(response, AccountManager.ERROR_CODE_REMOTE_EXCEPTION,
                        "Account deadline unavailable");
                return;
            }
            accepted.abandon();
            synchronized (lock) { accepted.preparing = false; accepted.dispatchLocked(); }
            throw invalid;
        }
    }

    /** Attach a continuation to the current worker's admission, if any. */
    Session session(Runnable cancel) {
        Request request = current.get();
        if (request == null) return null;
        Session session = new Session(request, cancel);
        boolean cancelled;
        synchronized (lock) {
            cancelled = request.terminal;
            if (!cancelled) request.sessions.add(session);
            else session.closed = true;
        }
        if (cancelled) cancel.run();
        return session;
    }

    /** Keep the first captured identity for each backend until outbound delivery. */
    boolean guard(String key, BooleanSupplier valid) {
        Request request = current.get();
        if (request == null) return true;
        boolean added;
        synchronized (lock) {
            if (request.terminal) return false;
            added = request.guards.containsKey(key) || request.guards.size() < MAX_DEPENDENCIES;
            if (added) request.guards.putIfAbsent(key, valid);
            else request.failLocked(AccountManager.ERROR_CODE_REMOTE_EXCEPTION,
                    "Account dependency limit reached");
        }
        if (!added) request.cancelSessions();
        return added;
    }

    void callerRemoved(String packageName) {
        ArrayList<Request> affected = new ArrayList<>();
        synchronized (lock) {
            String prefix = packageName + "\u0000";
            for (Request request : requests) {
                if (request.caller.startsWith(prefix)) affected.add(request);
            }
        }
        for (Request request : affected) request.callerChanged();
    }

    final class Session implements AutoCloseable {
        private final Request request;
        private Runnable cancel;
        private boolean closed;
        Session(Request request, Runnable cancel) { this.request = request; this.cancel = cancel; }
        long deadline() { return request.deadline; }
        void fail(int code, String message) { request.fail(code, message); }

        /** Retain an actual service-connection/IPC callback until it really returns. */
        Lease enter() {
            synchronized (lock) {
                if (closed || request.terminal) return null;
                request.externalCalls++;
            }
            return new Lease() {
                private boolean released;
                @Override public void close() {
                    synchronized (lock) {
                        if (released) return;
                        released = true;
                        request.externalCalls--;
                        request.dispatchLocked();
                    }
                }
            };
        }

        @Override public void close() {
            synchronized (lock) {
                if (closed) return;
                closed = true;
                cancel = null;
                request.sessions.remove(this);
                request.dispatchLocked();
            }
        }
    }

    private record Delivery(Bundle result, int code, String message, boolean terminal) { }

    private final class Request implements Runnable, IBinder.DeathRecipient {
        final String caller;
        final long deadline = uptime.getAsLong() + TIMEOUT_MILLIS;
        final Object producing = new Object();
        final LinkedHashSet<Session> sessions = new LinkedHashSet<>();
        final Map<String, BooleanSupplier> guards = new HashMap<>();
        final ArrayDeque<Delivery> deliveries = new ArrayDeque<>();
        final Runnable dispatch = this::drain;
        IAccountManagerResponse target;
        BooleanSupplier valid;
        IBinder binder;
        Runnable operation;
        ScheduledFuture<?> expiry, retry;
        boolean preparing = true, workOwned, dispatchOwned, terminal, abandoned, retired;
        boolean terminalDispatched;
        int externalCalls, resultOwners;
        final IAccountManagerResponse response = new IAccountManagerResponse() {
            @Override public IBinder asBinder() { return null; } // The admission owns the real death link.
            @Override public void onResult(Bundle value) { result(value); }
            @Override public void onError(int code, String message) { fail(code, message); }
        };

        Request(String caller, IAccountManagerResponse target, BooleanSupplier valid) {
            this.caller = caller; this.target = target; this.valid = valid;
        }

        void watch() {
            IAccountManagerResponse response;
            synchronized (lock) { response = target; }
            IBinder watching = response == null ? null : response.asBinder();
            if (watching == null) return;
            try { watching.linkToDeath(this, 0); }
            catch (RemoteException dead) { abandon(); return; }
            // A synchronous death during linkToDeath cannot escape cleanup: the
            // preparing flag retains this request until the link is installed.
            synchronized (lock) { binder = watching; }
        }

        @Override public void binderDied() { abandon(); }

        @Override public void run() {
            Runnable action = null;
            try {
                BooleanSupplier identity;
                synchronized (lock) { identity = terminal ? null : valid; }
                boolean currentIdentity = identity != null && identity.getAsBoolean();
                synchronized (lock) {
                    if (!terminal && !currentIdentity)
                        failLocked(AccountManager.ERROR_CODE_CANCELED, "Account caller changed");
                    // A delayed timer cannot allow expired queued work to bind.
                    if (!terminal && uptime.getAsLong() >= deadline)
                        failLocked(AccountManager.ERROR_CODE_REMOTE_EXCEPTION, "timeout");
                    if (!terminal) action = operation;
                    operation = null;
                }
                if (action != null) {
                    current.set(this);
                    action.run();
                }
            } catch (Throwable failure) {
                fail(AccountManager.ERROR_CODE_REMOTE_EXCEPTION, "Account operation failed");
            } finally {
                current.remove();
                action = null;
                synchronized (lock) {
                    workOwned = false;
                    if (!terminal && sessions.isEmpty()) terminal = true;
                    dispatchLocked();
                }
            }
        }

        void result(Bundle supplied) {
            boolean cancelSessions = false;
            synchronized (producing) {
                synchronized (lock) {
                    if (terminal) return;
                    if (uptime.getAsLong() >= deadline) {
                        failLocked(AccountManager.ERROR_CODE_REMOTE_EXCEPTION, "timeout");
                        cancelSessions = true;
                    } else if (resultOwners >= MAX_RESULTS) {
                        failLocked(AccountManager.ERROR_CODE_REMOTE_EXCEPTION,
                                "Account response queue full");
                        cancelSessions = true;
                    } else {
                        resultOwners++;
                        externalCalls++; // The copy is owned before it begins.
                    }
                }
                if (!cancelSessions) {
                    Bundle copy = null;
                    try {
                        copy = supplied == null ? new Bundle() : new Bundle(supplied);
                        boolean continuing = copy.containsKey(AccountManager.KEY_INTENT);
                        synchronized (lock) {
                            if (terminal) { resultOwners--; copy = null; }
                            else {
                                deliveries.addLast(new Delivery(copy, 0, null, !continuing));
                                copy = null;
                                if (!continuing) terminal = true;
                                dispatchLocked();
                            }
                        }
                    } catch (Throwable malformed) {
                        synchronized (lock) {
                            resultOwners--;
                            failLocked(AccountManager.ERROR_CODE_INVALID_RESPONSE,
                                    "Invalid authenticator response");
                        }
                        cancelSessions = true;
                    } finally {
                        copy = null;
                        synchronized (lock) { externalCalls--; dispatchLocked(); }
                    }
                }
            }
            if (cancelSessions) cancelSessions();
        }

        void fail(int code, String message) {
            synchronized (lock) { failLocked(code, message); }
            cancelSessions();
        }

        void failLocked(int code, String message) {
            if (terminal) return;
            terminal = true;
            operation = null;
            if (workers.remove(this)) workOwned = false;
            // Reserve one terminal control envelope beyond the bounded accepted
            // results. It follows them; saturation never discards a published Intent.
            deliveries.addLast(new Delivery(null, code, message, true));
            dispatchLocked();
        }

        void callerChanged() {
            synchronized (lock) {
                if (retired || abandoned || terminalDispatched) return;
                terminal = true;
                operation = null;
                if (workers.remove(this)) workOwned = false;
                for (Delivery delivery : deliveries) if (delivery.result() != null) resultOwners--;
                deliveries.clear();
                deliveries.addLast(new Delivery(null, AccountManager.ERROR_CODE_CANCELED,
                        "Account caller changed", true));
                dispatchLocked();
            }
            cancelSessions();
        }

        void expire() {
            synchronized (lock) {
                if (retired) return;
                if (!terminal && uptime.getAsLong() < deadline) {
                    expiry = schedule(this::expire, deadline - uptime.getAsLong());
                    return;
                }
                if (!terminal) failLocked(AccountManager.ERROR_CODE_REMOTE_EXCEPTION, "timeout");
                dispatchLocked();
            }
            cancelSessions();
        }

        void abandon() {
            synchronized (lock) {
                abandoned = true;
                terminal = true;
                operation = null;
                if (workers.remove(this)) workOwned = false;
                for (Delivery delivery : deliveries) if (delivery.result() != null) resultOwners--;
                deliveries.clear();
                dispatchLocked();
            }
            cancelSessions();
        }

        void cancelSessions() {
            ArrayList<Runnable> cancels = new ArrayList<>();
            synchronized (lock) {
                if (!terminal) return;
                for (Session session : sessions) if (session.cancel != null) cancels.add(session.cancel);
            }
            // These hooks only retire Answer state and wake its initial waiter.
            // They never call the application or wait for its delivery lock.
            for (Runnable cancel : cancels) cancel.run();
        }

        void dispatchLocked() {
            if (retired || dispatchOwned) return;
            dispatchOwned = true;
            callbacks.getQueue().add(dispatch);
            startDispatcherLocked();
        }

        void startDispatcherLocked() {
            try { callbacks.prestartCoreThread(); }
            catch (RuntimeException | Error unavailable) {
                // One queue entry remains owned. This request's original deadline
                // keeps the timer alive while dispatcher startup is retried.
                if (retry == null) retry = schedule(this::retryDispatcher, RETRY_MILLIS);
            }
        }

        void retryDispatcher() {
            synchronized (lock) {
                retry = null;
                if (!retired && dispatchOwned) startDispatcherLocked();
            }
        }

        boolean outputValid() {
            BooleanSupplier identity;
            ArrayList<BooleanSupplier> dependencies;
            synchronized (lock) {
                identity = valid;
                dependencies = new ArrayList<>(guards.values());
            }
            if (identity == null || !identity.getAsBoolean()) return false;
            for (BooleanSupplier dependency : dependencies) if (!dependency.getAsBoolean()) return false;
            return true;
        }

        boolean callerValid() {
            BooleanSupplier identity;
            synchronized (lock) { identity = valid; }
            return identity != null && identity.getAsBoolean();
        }

        void drain() {
            for (;;) {
                Delivery delivery;
                IAccountManagerResponse response;
                IBinder unlink = null;
                boolean finish;
                synchronized (lock) {
                    if (retry != null) { retry.cancel(false); retry = null; }
                    delivery = deliveries.pollFirst();
                    response = target;
                    finish = delivery == null && !preparing && !workOwned
                            && externalCalls == 0 && sessions.isEmpty();
                    if (finish) {
                        unlink = binder;
                        binder = null;
                    } else if (delivery == null) {
                        dispatchOwned = false;
                        return;
                    }
                }
                if (finish) {
                    // Keep admission charged until this final external Binder call
                    // really returns, too. No app/platform call holds lock.
                    try { if (unlink != null) unlink.unlinkToDeath(this, 0); }
                    catch (RuntimeException ignored) { }
                    synchronized (lock) { dispatchOwned = false; removeLocked(); }
                    return;
                }
                try {
                    boolean deliver;
                    synchronized (lock) { deliver = !abandoned; }
                    boolean identity = deliver && (delivery.result() == null ? callerValid() : outputValid());
                    if (deliver && !identity) {
                        // Revalidate close to outbound IPC, after waiting for the
                        // response lane. A retired installation receives no token.
                        synchronized (lock) {
                            deliver = !abandoned && !terminalDispatched;
                            terminalDispatched = true;
                        }
                        if (deliver && response != null)
                            response.onError(AccountManager.ERROR_CODE_CANCELED,
                                    "Account access changed");
                        abandon();
                        continue;
                    }
                    synchronized (lock) {
                        deliver &= !abandoned && !terminalDispatched;
                        if (deliver && delivery.terminal()) terminalDispatched = true;
                    }
                    if (deliver && response != null) {
                        if (delivery.result() != null) response.onResult(delivery.result());
                        else response.onError(delivery.code(), delivery.message());
                    }
                } catch (Throwable gone) {
                    abandon();
                } finally {
                    synchronized (lock) { if (delivery.result() != null) resultOwners--; }
                    delivery = null;
                    response = null;
                }
            }
        }

        void removeLocked() {
            if (retired) return;
            retired = true;
            if (expiry != null) { expiry.cancel(false); expiry = null; }
            if (retry != null) { retry.cancel(false); retry = null; }
            target = null; valid = null; operation = null;
            guards.clear();
            deliveries.clear();
            requests.remove(this);
            int count = callers.get(caller) - 1;
            if (count == 0) callers.remove(caller);
            else callers.put(caller, count);
        }
    }
}
