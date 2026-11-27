/* Copyright (C) 2026 The Gesher Authors; SPDX-License-Identifier: Apache-2.0 */
package com.gesher.server;

import android.accounts.AccountManager;
import android.accounts.IAccountManagerResponse;
import android.content.ComponentName;
import android.content.Intent;
import android.os.Bundle;
import android.os.IBinder;
import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.ScheduledThreadPoolExecutor;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.BooleanSupplier;

/** Complete production owner, with deliberately blocked local operation/callback endpoints. */
public final class AccountAdmissionHost {
    private static int checks;
    private static void check(boolean condition, String text) {
        if (!condition) throw new AssertionError(text);
        checks++;
    }
    private static void await(CountDownLatch latch) {
        try { if (!latch.await(30, TimeUnit.SECONDS)) throw new AssertionError("fixture wait"); }
        catch (InterruptedException e) { Thread.currentThread().interrupt(); throw new AssertionError(e); }
    }
    private static void until(BooleanSupplier done, String message) {
        long limit = System.nanoTime() + TimeUnit.SECONDS.toNanos(30);
        while (!done.getAsBoolean() && System.nanoTime() < limit) {
            try { Thread.sleep(2); }
            catch (InterruptedException e) { throw new AssertionError(e); }
        }
        check(done.getAsBoolean(), message);
    }
    private static Object get(Object owner, String name) {
        try { Field f=owner.getClass().getDeclaredField(name); f.setAccessible(true); return f.get(owner); }
        catch (ReflectiveOperationException e) { throw new AssertionError(e); }
    }
    private static void set(Object owner, String name, Object value) {
        try { Field f=owner.getClass().getDeclaredField(name); f.setAccessible(true); f.set(owner,value); }
        catch (ReflectiveOperationException e) { throw new AssertionError(e); }
    }
    private static Object call(Object owner, String name, Class<?>[] types, Object... args) {
        try { Method m=owner.getClass().getDeclaredMethod(name,types); m.setAccessible(true); return m.invoke(owner,args); }
        catch (ReflectiveOperationException e) { throw new AssertionError(e); }
    }

    private static final class Response implements IAccountManagerResponse {
        final AtomicInteger results=new AtomicInteger(), errors=new AtomicInteger();
        final AtomicInteger finished=new AtomicInteger();
        final List<Integer> values=Collections.synchronizedList(new ArrayList<>());
        volatile int code;
        volatile String message;
        volatile Runnable resultAction=()->{};
        volatile IBinder binder;
        @Override public IBinder asBinder() { return binder; }
        @Override public void onResult(Bundle value) {
            results.incrementAndGet(); values.add(value.getInt("value"));
            try { resultAction.run(); } finally { finished.incrementAndGet(); }
        }
        @Override public void onError(int value, String why) {
            code=value; message=why; errors.incrementAndGet(); finished.incrementAndGet();
        }
    }

    private static final class Harness implements AutoCloseable {
        final AtomicLong clock=new AtomicLong(1000);
        final AccountRequests owner=new AccountRequests(clock::get);
        final Object lock=get(owner,"lock");
        final ThreadPoolExecutor workers=(ThreadPoolExecutor)get(owner,"workers");
        final ThreadPoolExecutor callbacks=(ThreadPoolExecutor)get(owner,"callbacks");
        final ScheduledThreadPoolExecutor timers=(ScheduledThreadPoolExecutor)get(owner,"timers");
        int size() { synchronized(lock) { return ((Set<?>)get(owner,"requests")).size(); } }
        Object first() { synchronized(lock) { return ((Set<?>)get(owner,"requests")).iterator().next(); } }
        void empty() { until(()->size()==0,"admission was not retired");
            check(workers.getQueue().isEmpty()&&callbacks.getQueue().isEmpty(),"retired owner retained runnable");
            check(timers.getQueue().isEmpty(),"retired owner retained timer");
            synchronized(lock) { check(((Map<?,?>)get(owner,"callers")).isEmpty(),"retired caller quota"); }
        }
        @Override public void close() {
            workers.shutdownNow(); callbacks.shutdownNow(); timers.shutdownNow();
        }
    }

    private static void send(IAccountManagerResponse target, Bundle result) {
        try { target.onResult(result); }
        catch (android.os.RemoteException e) { throw new AssertionError(e); }
    }

    private static Bundle value(int n, boolean login) {
        Bundle b=new Bundle(); b.putInt("value",n);
        if (login) b.putParcelable(AccountManager.KEY_INTENT,new Intent("fixture.login"));
        return b;
    }

    private static void burst(int count) {
        try (Harness h=new Harness()) {
            CountDownLatch release=new CountDownLatch(1);
            AtomicInteger prepared=new AtomicInteger(), entered=new AtomicInteger();
            Response response=new Response();
            try {
                for (int i=0;i<count;i++) {
                    h.owner.execute("caller-"+i,response,()->true, target->{
                        prepared.incrementAndGet();
                        return ()->{entered.incrementAndGet();await(release);send(target,value(7,false));};
                    });
                }
                int accepted=Math.min(count,AccountRequests.MAX_REQUESTS);
                until(()->entered.get()==Math.min(accepted,AccountRequests.MAX_WORKERS),"worker demand");
                check(prepared.get()==accepted,"rejected work reached input preparation");
                check(h.size()==accepted,"queued/running admission count");
                check(response.errors.get()==count-accepted,"overload errors");
                check(h.workers.getLargestPoolSize()<=AccountRequests.MAX_WORKERS,"worker growth");
                check(h.workers.getQueue().size()<=AccountRequests.MAX_REQUESTS,"queue growth");
            } finally { release.countDown(); }
            h.empty();
            check(response.results.get()==Math.min(count,AccountRequests.MAX_REQUESTS),"accepted burst results");
            System.out.println("burst="+count+" prepared="+prepared+" workers="+h.workers.getLargestPoolSize());
        }
    }

    private static void callerBudget() {
        try (Harness h=new Harness()) {
            CountDownLatch release=new CountDownLatch(1);
            Response first=new Response(), other=new Response();
            AtomicInteger prepared=new AtomicInteger();
            try {
                for(int i=0;i<128;i++) h.owner.execute("one\u0000code",first,()->true,target->{
                    prepared.incrementAndGet();return ()->{await(release);send(target,value(1,false));};
                });
                h.owner.execute("other\u0000code",other,()->true,target->()->send(target,value(2,false)));
                check(prepared.get()==64&&first.errors.get()==64,"per-caller admission limit");
                check(h.size()==65,"one caller consumed every request slot");
                // All execution workers can be inside uncancelable calls from one
                // caller. Other accepted work is queued until actual capacity returns.
                check(other.errors.get()==0,"second caller incorrectly rejected");
            } finally { release.countDown(); }
            h.empty(); check(other.results.get()==1,"queued other-caller work never progressed");
        }
    }

    private static void concurrentBurst() throws Exception {
        try(Harness h=new Harness()){
            CountDownLatch start=new CountDownLatch(1),release=new CountDownLatch(1);
            AtomicInteger prepared=new AtomicInteger();AtomicReference<Throwable> failure=new AtomicReference<>();
            Response response=new Response();List<Thread> producers=new ArrayList<>();
            try{
                for(int i=0;i<32;i++){
                    int producer=i;
                    Thread thread=new Thread(()->{
                        try{
                            await(start);
                            for(int j=0;j<32;j++)h.owner.execute("parallel-"+producer+"-"+j,response,()->true,target->{
                                prepared.incrementAndGet();return ()->{await(release);send(target,value(1,false));};
                            });
                        }catch(Throwable broken){failure.compareAndSet(null,broken);}
                    });
                    producers.add(thread);thread.start();
                }
                start.countDown();
                for(Thread producer:producers){producer.join(30000);check(!producer.isAlive(),"concurrent producer blocked");}
                check(failure.get()==null,"concurrent admission threw: "+failure.get());
                check(prepared.get()==256&&h.size()==256,"concurrent admission exceeded/lost credit");
                check(response.errors.get()==768,"concurrent overload count");
                check(h.workers.getLargestPoolSize()<=32,"concurrent burst worker growth");
            }finally{start.countDown();release.countDown();}
            h.empty();check(response.results.get()==256,"concurrent accepted result count");
        }
    }

    private static void blockedCallbacks() {
        try (Harness h=new Harness()) {
            CountDownLatch release=new CountDownLatch(1), entered=new CountDownLatch(4);
            Response response=new Response();
            response.resultAction=()->{entered.countDown();await(release);};
            try {
                for(int i=0;i<256;i++) h.owner.execute("c"+i,response,()->true,
                        target->()->send(target,value(1,false)));
                await(entered);
                until(()->h.workers.getActiveCount()==0,"operation workers did not return");
                check(h.size()==256,"finished worker recycled blocked callback owner");
                check(h.callbacks.getPoolSize()==4,"callback worker count");
                AtomicBoolean copied=new AtomicBoolean();
                Response rejected=new Response();
                h.owner.execute("extra",rejected,()->true,target->{copied.set(true);return ()->{};});
                check(!copied.get()&&rejected.errors.get()==1,"full completion ownership admitted input");
            } finally { release.countDown(); }
            h.empty(); check(response.results.get()==256,"blocked callback burst lost results");
        }
    }

    private static void continuationAndExternalCall() throws Exception {
        try (Harness h=new Harness()) {
            Response response=new Response();
            AtomicReference<AccountRequests.Session> session=new AtomicReference<>();
            AtomicReference<IAccountManagerResponse> reply=new AtomicReference<>();
            AtomicReference<AutoCloseable> external=new AtomicReference<>();
            h.owner.execute("caller",response,()->true,target->()->{
                AccountRequests.Session lease=h.owner.session(()->session.get().close());
                session.set(lease); external.set(lease.enter()); reply.set(target);
                send(target,value(10,true));
            });
            until(()->response.results.get()==1,"login result");
            until(()->h.workers.getActiveCount()==0,"initial worker remained");
            check(h.size()==1,"interactive continuation lost admission");
            send(reply.get(),value(11,false));session.get().close();
            until(()->response.results.get()==2,"final result");
            check(h.size()==1,"active external IPC lost admission");
            external.get().close(); h.empty();
            check(response.values.equals(List.of(10,11)),"login/final ordering");
        }
    }

    private static void queuedDeadline() {
        try (Harness h=new Harness()) {
            CountDownLatch release=new CountDownLatch(1), entered=new CountDownLatch(32);
            Response response=new Response();AtomicInteger lateBackend=new AtomicInteger();
            try {
                for(int i=0;i<32;i++) h.owner.execute("blocked"+i,response,()->true,target->()->{
                    entered.countDown();await(release);send(target,value(1,false));
                });
                await(entered);
                h.owner.execute("queued",response,()->true,target->()->{
                    lateBackend.incrementAndGet();send(target,value(2,false));
                });
                // Do not execute the delayed timer. The dequeued producer itself
                // must consult the unchanged production uptime deadline.
                h.clock.addAndGet(AccountRequests.TIMEOUT_MILLIS);
            } finally { release.countDown(); }
            h.empty();
            check(lateBackend.get()==0,"expired queued request entered backend");
            check(response.results.get()==0&&response.errors.get()==33,"late successful results escaped deadline");
        }
    }

    private static void activeTimeout() throws Exception {
        try (Harness h=new Harness()) {
            CountDownLatch release=new CountDownLatch(1), entered=new CountDownLatch(1);
            Response response=new Response();
            try {
                h.owner.execute("caller",response,()->true,target->()->{
                    entered.countDown();await(release);send(target,value(1,false));
                });
                await(entered);Object request=h.first();
                h.clock.addAndGet(AccountRequests.TIMEOUT_MILLIS);
                call(request,"expire",new Class<?>[0]);
                until(()->response.errors.get()==1,"active timeout callback");
                check(h.size()==1,"timeout freed a running operation");
            } finally { release.countDown(); }
            h.empty();check(response.errors.get()==1&&response.results.get()==0,"late reply after timeout");
        }
    }

    private static void deathAndRemoval() {
        for(boolean removal:List.of(false,true)) try (Harness h=new Harness()) {
            CountDownLatch release=new CountDownLatch(1), entered=new CountDownLatch(1);
            Response response=new Response();
            AtomicReference<IBinder.DeathRecipient> death=new AtomicReference<>();
            AtomicInteger links=new AtomicInteger(),unlinks=new AtomicInteger();
            response.binder=(IBinder)Proxy.newProxyInstance(IBinder.class.getClassLoader(),new Class<?>[]{IBinder.class},(p,m,a)->{
                return switch(m.getName()) {
                    case "linkToDeath"->{links.incrementAndGet();death.set((IBinder.DeathRecipient)a[0]);yield null;}
                    case "unlinkToDeath"->{unlinks.incrementAndGet();yield true;}
                    case "isBinderAlive","pingBinder"->true;
                    default->null;
                };
            });
            try {
                h.owner.execute("client\u0000code",response,()->true,target->()->{
                    entered.countDown();await(release);send(target,value(1,false));
                });await(entered);
                if(removal)h.owner.callerRemoved("client");else death.get().binderDied();
                if(removal)until(()->response.errors.get()==1,"removal response");
                check(h.size()==1,"cancellation freed active work");
            }finally{release.countDown();}
            h.empty();check(links.get()==1&&unlinks.get()==1,"death link lifetime");
            check(response.results.get()==0&&response.errors.get()==(removal?1:0),"death/removal callback contract");
        }
    }

    private static void boundedResults() {
        try (Harness h=new Harness()) {
            CountDownLatch release=new CountDownLatch(1),entered=new CountDownLatch(1);
            AtomicReference<IAccountManagerResponse> reply=new AtomicReference<>();
            AtomicReference<AccountRequests.Session> lease=new AtomicReference<>();
            Response response=new Response();response.resultAction=()->{entered.countDown();await(release);};
            try {
                h.owner.execute("caller",response,()->true,target->()->{
                    lease.set(h.owner.session(()->lease.get().close()));reply.set(target);send(target,value(0,true));
                });await(entered);
                for(int i=1;i<1000;i++)send(reply.get(),value(i,true));
                Object request=h.first();
                synchronized(h.lock){
                    check(((java.util.Collection<?>)get(request,"deliveries")).size()<=AccountRequests.MAX_RESULTS,
                            "unbounded callback envelopes behind blocked app");
                    check((Integer)get(request,"resultOwners")==AccountRequests.MAX_RESULTS,"result owners limit");
                }
            }finally{release.countDown();}
            h.empty();check(response.results.get()==8&&response.errors.get()==1,"response overflow lost/duplicated accepted callbacks");
            check(response.values.equals(List.of(0,1,2,3,4,5,6,7)),"response overflow order");
        }
    }

    private static void startupFailures() {
        try(Harness h=new Harness()){
            AtomicInteger prepared=new AtomicInteger();Response response=new Response();
            h.timers.setThreadFactory(r->{throw new OutOfMemoryError("fixture timer start");});
            h.owner.execute("caller",response,()->true,target->{prepared.incrementAndGet();return ()->{};});
            check(prepared.get()==0&&response.errors.get()==1,"failed timer copied/admitted input");
            h.empty();
        }
        try(Harness h=new Harness()){
            Response response=new Response();
            h.workers.setThreadFactory(r->{throw new OutOfMemoryError("fixture worker start");});
            h.owner.execute("caller",response,()->true,target->()->{throw new AssertionError("not started");});
            h.empty();check(response.errors.get()==1,"worker failure stranded response");
        }
        try(Harness h=new Harness()){
            Response response=new Response();AtomicInteger attempts=new AtomicInteger();
            java.util.concurrent.ThreadFactory ordinary=h.callbacks.getThreadFactory();
            h.callbacks.setThreadFactory(r->{if(attempts.incrementAndGet()<=3)throw new OutOfMemoryError("fixture callback start");return ordinary.newThread(r);});
            h.owner.execute("caller",response,()->true,target->()->send(target,value(42,false)));
            until(()->response.results.get()==1,"callback startup retry did not deliver");
            h.empty();check(response.values.equals(List.of(42))&&attempts.get()>=4,"callback retry duplicated payload");
        }
    }

    private static void reentryAndThrowingCallback() {
        try(Harness h=new Harness()){
            Response first=new Response(),second=new Response();
            first.resultAction=()->h.owner.execute("reentered",second,()->true,target->()->send(target,value(2,false)));
            h.owner.execute("caller",first,()->true,target->()->send(target,value(1,false)));
            until(()->second.results.get()==1,"reentrant request failed");h.empty();
            Response throwing=new Response(),following=new Response();
            throwing.resultAction=()->{throw new AssertionError("fixture client error");};
            h.owner.execute("throw",throwing,()->true,target->()->send(target,value(3,false)));
            h.owner.execute("follow",following,()->true,target->()->send(target,value(4,false)));
            until(()->following.results.get()==1,"throwing client stopped the lane");h.empty();
            check(throwing.results.get()==1&&throwing.errors.get()==0,"callback failure replayed terminal response");
        }
    }

    private static void preparingCancellation() throws Exception {
        try(Harness h=new Harness()){
            Response response=new Response();CountDownLatch entered=new CountDownLatch(1),release=new CountDownLatch(1);
            AtomicInteger backend=new AtomicInteger();
            Thread caller=new Thread(()->h.owner.execute("client\u0000code",response,()->true,target->{
                entered.countDown();await(release);return ()->backend.incrementAndGet();
            }));
            try{
                caller.start();await(entered);
                h.owner.callerRemoved("client");
                until(()->response.errors.get()==1,"preparing cancellation response");
                check(h.size()==1,"preparation reference released before copy returned");
            }finally{release.countDown();caller.join(30000);}
            check(!caller.isAlive(),"preparation did not return");h.empty();
            check(backend.get()==0,"cancelled preparation entered backend");
        }
    }

    private static void responseIdentity() {
        try(Harness h=new Harness()){
            CountDownLatch release=new CountDownLatch(1),entered=new CountDownLatch(4);
            Response blocked=new Response();blocked.resultAction=()->{entered.countDown();await(release);};
            Response response=new Response();AtomicBoolean valid=new AtomicBoolean(true);
            try{
                for(int i=0;i<4;i++)h.owner.execute("blocked"+i,blocked,()->true,target->()->send(target,value(1,false)));
                await(entered);
                h.owner.execute("target",response,valid::get,target->()->send(target,value(2,false)));
                until(()->h.workers.getActiveCount()==0,"identity result production");
                valid.set(false);
            }finally{release.countDown();}
            h.empty();
            check(response.results.get()==0&&response.errors.get()==1
                    &&response.code==AccountManager.ERROR_CODE_CANCELED,"retired identity received queued result");
        }
    }

    private static void backendIdentity() {
        try(Harness h=new Harness()){
            CountDownLatch release=new CountDownLatch(1),entered=new CountDownLatch(4);
            Response blocked=new Response();blocked.resultAction=()->{entered.countDown();await(release);};
            Response response=new Response();AtomicBoolean valid=new AtomicBoolean(true);
            try{
                for(int i=0;i<4;i++)h.owner.execute("blocked"+i,blocked,()->true,target->()->send(target,value(1,false)));
                await(entered);
                h.owner.execute("client",response,()->true,target->()->{
                    h.owner.guard("authenticator",valid::get);
                    // Repeated same-owner feature queries retain the first identity.
                    h.owner.guard("authenticator",()->true);
                    send(target,value(2,false));
                });
                until(()->h.workers.getActiveCount()==0,"backend identity result production");
                valid.set(false);
            }finally{release.countDown();}
            h.empty();check(response.results.get()==0&&response.errors.get()==1
                    &&response.code==AccountManager.ERROR_CODE_CANCELED,"retired backend delivered queued result");
            Response error=new Response();
            h.owner.execute("client",error,()->true,target->()->{
                h.owner.guard("unavailable",()->false);
                try{target.onError(AccountManager.ERROR_CODE_BAD_AUTHENTICATION,"original error");}
                catch(android.os.RemoteException impossible){throw new AssertionError(impossible);}
            });
            h.empty();check(error.errors.get()==1&&error.code==AccountManager.ERROR_CODE_BAD_AUTHENTICATION,
                    "backend revalidation changed an authenticator error");
            Response overflow=new Response();
            h.owner.execute("client",overflow,()->true,target->()->{
                for(int i=0;i<=AccountRequests.MAX_DEPENDENCIES;i++)h.owner.guard("owner"+i,()->true);
                send(target,value(3,false));
            });
            h.empty();check(overflow.results.get()==0&&overflow.errors.get()==1
                    &&overflow.code==AccountManager.ERROR_CODE_REMOTE_EXCEPTION,"dependency overflow was unbounded/silent");
        }
    }

    private static Object construct(Class<?> type, Class<?>[] parameters,Object... values) {
        try{Constructor<?> c=type.getDeclaredConstructor(parameters);c.setAccessible(true);return c.newInstance(values);}
        catch(ReflectiveOperationException e){throw new AssertionError(e);}
    }

    private static void serviceAnswerOwnership() throws Exception {
        for(String terminal:List.of("success","timeout","removal","validation","incoming","owner-removal","construction")){
            PackageManagerService packages=new PackageManagerService(Collections.emptyList());
            AccountManagerService service=new AccountManagerService(null,packages,false);
            AccountRequests requests=(AccountRequests)get(service,"mRequests");Object lock=get(requests,"lock");
            AtomicLong clock=new AtomicLong(1000);set(service,"mSessionUptimeMillis",(java.util.function.LongSupplier)clock::get);
            Class<?> auth=Class.forName("com.gesher.server.AccountManagerService$Authenticator");
            Class<?> caller=Class.forName("com.gesher.server.AccountManagerService$Caller");
            Class<?> answerType=Class.forName("com.gesher.server.AccountManagerService$Answer");
            Class<?> checkType=Class.forName("com.gesher.server.AccountManagerService$ResultCheck");
            Object authenticator=construct(auth,new Class<?>[]{String.class,ComponentName.class,int.class,int.class,int.class,int.class,boolean.class},
                    "fixture.type",new ComponentName("fixture.authenticator","fixture.authenticator.Service"),0,0,0,0,false);
            Intent original=new Intent("fixture.login").setComponent(
                    new ComponentName("fixture.authenticator","fixture.authenticator.Login"));
            Bundle offered=new Bundle();offered.putParcelable(AccountManager.KEY_INTENT,original);
            Bundle checked=(Bundle)call(service,"validatedResult",new Class<?>[]{auth,Bundle.class,android.accounts.Account.class},
                    authenticator,offered,null);
            original.setComponent(new ComponentName("other.package","other.package.Activity"));
            Intent retained=checked.getParcelable(AccountManager.KEY_INTENT,Intent.class);
            check(retained!=original&&retained.getComponent().getPackageName().equals("fixture.authenticator"),
                    "validated login retained mutable external Intent identity");
            Response response=new Response();AtomicReference<Object> answer=new AtomicReference<>();
            CountDownLatch validating=new CountDownLatch(1),release=new CountDownLatch(1);
            Object validator=Proxy.newProxyInstance(checkType.getClassLoader(),new Class<?>[]{checkType},(p,m,a)->{
                if(terminal.equals("validation") || (terminal.equals("incoming") || terminal.equals("owner-removal"))
                        && ((Bundle)a[0]).getInt("value")==2){
                    validating.countDown();await(release);
                }return a[0];
            });
            Thread incoming=null;
            try{
                requests.execute("client\u0000code",response,()->true,target->()->{
                    if(terminal.equals("construction")){validating.countDown();await(release);}
                    Object value=construct(answerType,new Class<?>[]{AccountManagerService.class,auth,caller,IAccountManagerResponse.class},
                            service,authenticator,null,target);answer.set(value);
                    if(terminal.equals("construction"))return;
                    call(value,"onResult",new Class<?>[]{Bundle.class},value(1,true));
                    call(value,"deliverSession",new Class<?>[]{IAccountManagerResponse.class,checkType},target,validator);
                });
                if(terminal.equals("construction")){
                    await(validating);Object request;
                    synchronized(lock){request=((Set<?>)get(requests,"requests")).iterator().next();}
                    clock.addAndGet(AccountRequests.TIMEOUT_MILLIS);call(request,"expire",new Class<?>[0]);
                    until(()->response.errors.get()==1,"constructor deadline response");
                    synchronized(lock){check(((Set<?>)get(requests,"requests")).size()==1,"constructor worker lost admission");}
                    release.countDown();until(()->answer.get()!=null,"cancelled Answer constructor failed");
                    check((Boolean)get(answer.get(),"complete")&&get(answer.get(),"requestSession")==null,
                            "cancelled constructor retained its returned lease");
                    until(()->{synchronized(lock){return ((Set<?>)get(requests,"requests")).isEmpty();}},"constructor admission retained");
                    continue;
                }
                if(terminal.equals("validation"))await(validating);
                else until(()->response.results.get()==1,"production Answer login");
                Object value=answer.get();check((Boolean)get(value,"admitted"),"production Answer did not attach admission");
                check(get(value,"timeout")==null,"owned Answer duplicated admission deadline");
                if(terminal.equals("incoming") || terminal.equals("owner-removal")){
                    until(()->((ThreadPoolExecutor)get(requests,"workers")).getActiveCount()==0,
                            "initial operation did not return before continuation");
                    incoming=new Thread(()->call(value,"onResult",new Class<?>[]{Bundle.class},value(2,false)));
                    incoming.start();await(validating);
                }
                Object request;synchronized(lock){request=((Set<?>)get(requests,"requests")).iterator().next();}
                switch(terminal){
                    case "success"->call(value,"onResult",new Class<?>[]{Bundle.class},value(2,false));
                    case "removal"->requests.callerRemoved("client");
                    case "owner-removal"->service.packageRemoved("fixture.authenticator");
                    default->{
                        clock.addAndGet(AccountRequests.TIMEOUT_MILLIS);
                        // Must return even when validation owns Answer.deliveryLock.
                        call(request,"expire",new Class<?>[0]);
                    }
                }
                if(terminal.equals("incoming") || terminal.equals("owner-removal")){
                    until(()->response.errors.get()==1,"incoming validation timeout response");
                    synchronized(lock){check(((Set<?>)get(requests,"requests")).size()==1,
                            "closed session released admission during incoming validation");}
                    check(get(value,"requestSession")==null,"timeout did not close incoming continuation");
                }
                release.countDown();
                if(incoming!=null){incoming.join(30000);check(!incoming.isAlive(),"incoming callback did not return");}
                until(()->{synchronized(lock){return ((Set<?>)get(requests,"requests")).isEmpty();}},"production Answer retained admission");
                check((Boolean)get(value,"complete")&&get(value,"requestSession")==null,"production Answer retained its session lease");
                check(((CountDownLatch)get(value,"done")).getCount()==0,"production Answer initial waiter not woken");
                check(((List<?>)get(value,"pending")).isEmpty()&&get(value,"listener")==null,"production Answer retained payload");
                int expected=terminal.equals("validation")?0:terminal.equals("success")?2:1;
                check(response.results.get()==expected&&response.errors.get()==(terminal.equals("success")?0:1),"production Answer callback order/count");
            }finally{
                release.countDown();
                if(incoming!=null)incoming.join(30000);
                for(String name:List.of("workers","callbacks","timers"))((ExecutorService)get(requests,name)).shutdownNow();
                for(String name:List.of("mSessionTimeout","mCalls"))((ExecutorService)get(service,name)).shutdownNow();
                ((ExecutorService)get(packages,"mPackageEventExecutor")).shutdownNow();
            }
        }
    }

    private static void overloadedSessionFinish() {
        PackageManagerService packages=new PackageManagerService(Collections.emptyList());
        AccountManagerService service=new AccountManagerService(null,packages,false);
        AccountRequests requests=(AccountRequests)get(service,"mRequests");Object lock=get(requests,"lock");
        CountDownLatch release=new CountDownLatch(1),entered=new CountDownLatch(4);
        Response blocked=new Response();blocked.resultAction=()->{entered.countDown();await(release);};
        try{
            for(int i=0;i<256;i++)requests.execute("blocked"+i,blocked,()->true,target->()->send(target,value(1,false)));
            await(entered);
            Object client=call(service,"caller",new Class<?>[]{String.class},new Object[]{null});
            String key=(String)call(client,"key",new Class<?>[0]);int uid=(Integer)get(client,"uid");
            AccountSessions sessions=(AccountSessions)get(service,"mSessions");
            Bundle privateData=new Bundle();privateData.putString("secret","fixture-session-data");
            Bundle handle=sessions.issue(key,uid,"fixture.authenticator","fixture-code","fixture.type",null,privateData);
            Response response=new Response();
            service.finishSessionAsUser(response,handle,false,null,0);
            check(response.errors.get()==1&&response.code==AccountManager.ERROR_CODE_REMOTE_EXCEPTION,
                    "overloaded finish did not report resource error");
            AccountSessions.Pending retained=sessions.consume(handle,key,uid,pending->true);
            check(retained.data().getString("secret").equals("fixture-session-data"),
                    "overload consumed the one-shot session handle before admission");
        }finally{
            release.countDown();
            until(()->{synchronized(lock){return ((Set<?>)get(requests,"requests")).isEmpty();}},"overload fixture retained admission");
            for(String name:List.of("workers","callbacks","timers"))((ExecutorService)get(requests,name)).shutdownNow();
            for(String name:List.of("mSessionTimeout","mCalls"))((ExecutorService)get(service,name)).shutdownNow();
            ((ExecutorService)get(packages,"mPackageEventExecutor")).shutdownNow();
        }
    }

    private static void publicEntry() {
        PackageManagerService packages=new PackageManagerService(Collections.emptyList());
        AccountManagerService service=new AccountManagerService(null,packages,false);
        CountDownLatch release=new CountDownLatch(1);
        Response response=new Response();response.resultAction=()->await(release);
        try {
            for(int i=0;i<128;i++)service.getAccountsByFeatures(response,"com.google",new String[0],null);
            until(()->response.results.get()>=4,"public entry never dispatched its callbacks");
            // On the old complete service, every response blocks a distinct cached
            // pool worker; no AccountRequests code is on that public call path.
            until(()->response.errors.get()==64 || response.results.get()>AccountRequests.MAX_CALLBACK_WORKERS,
                    "public entry neither admitted/rejected nor dispatched its requests");
            System.out.println("publicRequests=128 blockedCallbacks="+response.results.get()
                    +" overloadErrors="+response.errors.get());
            check(response.results.get()<=AccountRequests.MAX_CALLBACK_WORKERS,
                    "public API created "+response.results+" blocked callback workers");
            check(response.errors.get()==64,"public API admission did not reject before work");
            Object owner=get(service,"mRequests");Object lock=get(owner,"lock");
            synchronized(lock){check(((Set<?>)get(owner,"requests")).size()==64,"public owner count");}
        }finally{
            release.countDown();
            until(()->response.finished.get()==128,"public callbacks lost");
            for(String name:List.of("mSessionTimeout","mCalls"))((ExecutorService)get(service,name)).shutdownNow();
            try{
                Object owner=get(service,"mRequests");
                for(String name:List.of("workers","callbacks","timers"))((ExecutorService)get(owner,name)).shutdownNow();
            }catch(AssertionError baseline){ if(!(baseline.getCause() instanceof NoSuchFieldException))throw baseline; }
            ((ExecutorService)get(packages,"mPackageEventExecutor")).shutdownNow();
        }
    }

    public static void main(String[] args) throws Exception {
        System.load(args[0]);
        publicEntry();
        if(args.length>1)return;
        for(int count:new int[]{1,32,256,1024})burst(count);
        concurrentBurst();overloadedSessionFinish();
        callerBudget();blockedCallbacks();continuationAndExternalCall();queuedDeadline();activeTimeout();
        deathAndRemoval();boundedResults();startupFailures();reentryAndThrowingCallback();
        preparingCancellation();responseIdentity();backendIdentity();serviceAnswerOwnership();
        System.out.println("AccountAdmissionHost passed: "+checks+" checks");
    }
}
