#!/usr/bin/env python3
# Copyright (C) 2026 The Gesher HaMeitarim Authors (גשר המיתרים); SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
"""Wiring contracts of the host shell's account list and removal (no build needed).

`gesher-app accounts` and `remove-account` and the Control Center's Accounts dialog reach the
device through GesherService; each link is checked here, so a renamed transaction, command or
control name cannot leave one end behind. Behavior is checked on Windows by hand, listed in
docs/he/11-wave6-manual-checks.md.
"""
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class HostAccountCommands(unittest.TestCase):
    def test_service_transactions_are_inside_the_checked_range(self):
        text = read("app/java/com/gesher/server/GesherService.java")
        self.assertIn("code > REMOVE_ACCOUNT", text)
        self.assertNotIn("code > SET_SPECIAL_ACCESS_VISIT", text)
        codes = [int(n) for n in re.findall(r"FIRST_CALL_TRANSACTION \+ (\d+);", text)]
        self.assertEqual(len(codes), len(set(codes)), "a transaction code is used twice")
        for name in ("ACCOUNTS", "REMOVE_ACCOUNT"):
            self.assertRegex(text, r"case %s:" % name)
            self.assertRegex(text, r"transact\(%s," % name)

    def test_the_device_implements_what_the_service_declares(self):
        server = read("app/java/com/gesher/server/SystemServer.java")
        self.assertIn("public String[] accounts()", server)
        self.assertIn("public boolean removeAccount(String type, String name)", server)
        accounts = read("app/java/com/gesher/server/AccountManagerService.java")
        self.assertIn("String[] hostAccountRows()", accounts)
        self.assertIn("boolean hostRemoveAccount(String type, String name)", accounts)
        # Host methods are not binder methods: an app must not reach them.
        self.assertNotRegex(accounts, r"public\s+(synchronized\s+)?(String\[\]|boolean)\s+host(AccountRows|RemoveAccount)")
        services = read("app/java/com/gesher/server/Services.java")
        self.assertIn("created.accounts = accounts;", services)

    def test_cli_commands_and_usage(self):
        text = read("app/java/com/gesher/app/Launcher.java")
        self.assertIn('case "accounts": return accounts(rest);', text)
        self.assertIn('case "remove-account": return removeAccount(rest);', text)
        self.assertIn("accounts | remove-account TYPE NAME", text)

    def test_control_center_names_match(self):
        xaml = read("tools/package/gesher-panel-accounts.xaml")
        dashboard = read("tools/package/gesher-panel-dashboard.xaml")
        script = read("tools/package/gesher-control-panel.ps1")
        view = read("tools/package/gesher-panel-view.ps1")
        self.assertIn("'accounts'", view)
        start = script.index("function Show-AccountsDialog")
        body = script[start:script.index("function Show-ProxyDialog", start)]
        names = re.findall(r"FindName\('(\w+)'\)", body)
        self.assertTrue(names)
        for name in names:
            self.assertIn('Name="%s"' % name, xaml)
        self.assertIn('Name="BtnAccounts"', dashboard)
        self.assertIn("$window.FindName('BtnAccounts')", script)
        for command in ("'accounts'", "'remove-account'"):
            self.assertIn(command, script)

    def test_messages_exist_in_both_languages(self):
        catalog = json.loads(read("tools/i18n/messages.json"))["messages"]
        keys = set(re.findall(r"Get-GesherText '(cp_accounts_\w+|cp_btn_accounts)'",
                              read("tools/package/gesher-control-panel.ps1")))
        keys |= set(re.findall(r"Text_(cp_accounts_\w+|cp_btn_accounts)\}",
                               read("tools/package/gesher-panel-dashboard.xaml")
                               + read("tools/package/gesher-panel-accounts.xaml")))
        keys |= {"accounts_count", "accounts_none", "account_removed", "account_not_found"}
        self.assertTrue(keys)
        for key in sorted(keys):
            self.assertIn(key, catalog, key)
            self.assertEqual(set(catalog[key]), {"en", "he"}, key)


if __name__ == "__main__":
    unittest.main()
