"""Unit and end-to-end tests for bin/garitta-digest (standard library only)."""
import importlib.machinery
import importlib.util
import io
import json
import os
import tempfile
import unittest
from contextlib import redirect_stdout
from datetime import timedelta

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load():
    loader = importlib.machinery.SourceFileLoader('garitta_digest', os.path.join(ROOT, 'bin', 'garitta-digest'))
    spec = importlib.util.spec_from_loader('garitta_digest', loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


EMAIL_YAML = """type: email           # Don't change
name: email_default
format: |
  {{range . -}}
    - not a list item {{.Value}}
  {{end -}}
smtp_host: smtp.example.org  # comment
smtp_username: alerts@example.org
smtp_password: "p#ss: word"
smtp_port: 465
encryption_type: ssltls
sender_name: "CrowdSec"
sender_email: alerts@example.org
email_subject: "Site - CrowdSec"
receiver_emails:
- a@example.org
- 'b@example.org'
---
"""


class Base(unittest.TestCase):
    def setUp(self):
        self.m = load()
        self.tmp = tempfile.TemporaryDirectory()
        self.d = self.tmp.name
        self.m.OPT['STATE_DIR'] = os.path.join(self.d, 'state')
        self.m.OPT['BLOCKLIST_STATUS'] = os.path.join(self.d, 'none')

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, name, text):
        path = os.path.join(self.d, name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'w') as f:
            f.write(text)
        return path

    def iso(self, minutes_ago, local=False):
        t = self.m.NOW - timedelta(minutes=minutes_ago)
        return (t.astimezone() if local else t).isoformat()


class TestParsing(Base):
    def test_smtp_conf(self):
        cfg = self.m.smtp_conf(self.write('email.yaml', EMAIL_YAML))
        self.assertEqual(cfg['smtp_host'], 'smtp.example.org')
        self.assertEqual(cfg['smtp_password'], 'p#ss: word')
        self.assertEqual(cfg['receiver_emails'], ['a@example.org', 'b@example.org'])
        self.assertEqual(cfg['email_subject'], 'Site - CrowdSec')

    def test_load_conf(self):
        self.m.load_conf(self.write('conf', 'SUBJECT="A - B"\nREPORT_LANG=it  # comment\n#MAX_ROWS=1\nBOGUS=1\n'))
        self.assertEqual(self.m.OPT['SUBJECT'], 'A - B')
        self.assertEqual(self.m.OPT['REPORT_LANG'], 'it')
        self.assertEqual(self.m.OPT['MAX_ROWS'], '300')
        self.assertNotIn('BOGUS', self.m.OPT)

    def test_whitelist_match(self):
        wl = self.m.Whitelist()
        wl.add('192.0.2.0/24', 'allowlist a', 'office')
        wl.add('2001:db8::1', 'allowlist a')
        wl.add('not-an-ip', 'x')
        self.assertEqual(wl.match('192.0.2.7'), ('allowlist a', 'office'))
        self.assertIsNotNone(wl.match('2001:db8::1'))
        self.assertIsNone(wl.match('198.51.100.1'))
        self.assertIsNone(wl.match('garbage'))

    def test_parser_whitelists(self):
        base = os.path.join(self.d, 'cs')
        self.write('cs/parsers/s02-enrich/mine.yaml',
                   'name: me/wl\nwhitelist:\n  reason: "offices"\n  ip:\n   - "192.0.2.1"\n  cidr:\n   - 10.1.0.0/16\n')
        self.write('cs/parsers/s02-enrich/expr.yaml', 'whitelist:\n  reason: x\n  expression:\n   - evt.X == 1\n')
        hub = self.write('hub.yaml', 'whitelist:\n  ip:\n   - 1.1.1.1\n')
        os.symlink(hub, os.path.join(base, 'parsers/s02-enrich/hub.yaml'))
        out = self.m.parser_whitelists(base)
        mine = out[os.path.join(base, 'parsers/s02-enrich/mine.yaml')]
        self.assertEqual(mine, ('offices', ['192.0.2.1', '10.1.0.0/16'], False))
        self.assertTrue(out[os.path.join(base, 'parsers/s02-enrich/expr.yaml')][2])
        self.assertEqual(len(out), 2)   # hub symlink ignored


class TestCollectors(Base):
    def setUp(self):
        super().setUp()
        self.wl = self.m.Whitelist()
        self.wl.add('192.0.2.10', 'allowlist offices', 'Rome')

    def test_crowdsec_overflows(self):
        self.m.OPT['CROWDSEC_LOG_DIR'] = self.d
        msg = "Ip {ip} performed 'crowdsecurity/ssh-bf' (6 events over 3s) at 2026-01-01 00:00:00 +0000 UTC"
        self.write('crowdsec.log', '\n'.join([
            f'time="{self.iso(10, True)}" level=info msg="{msg.format(ip="192.0.2.10")}"',
            f'time="{self.iso(10, True)}" level=info msg="{msg.format(ip="203.0.113.5")}"',
            f'time="{self.iso(3000, True)}" level=info msg="{msg.format(ip="192.0.2.10")}"',
        ]) + '\n')
        hits = self.m.crowdsec_overflows(self.m.NOW - timedelta(hours=24), self.wl)
        self.assertEqual([h['ip'] for h in hits], ['192.0.2.10'])
        self.assertIn('crowdsecurity/ssh-bf (6 events in 3s)', hits[0]['detail'])

    def test_fail2ban(self):
        now = self.m.NOW.astimezone()
        stamp = now.strftime('%Y-%m-%d %H:%M:%S')
        self.m.OPT['FAIL2BAN_LOG'] = self.write('fail2ban.log', '\n'.join([
            f'{stamp},054 fail2ban.actions        [867]: NOTICE  [sshd] Ban 203.0.113.9',
            f'{stamp},054 fail2ban.actions        [867]: NOTICE  [sshd] Restore Ban 203.0.113.8',
            f'{stamp},054 fail2ban.filter         [867]: INFO    [sshd] Ignore 192.0.2.10 by ip',
            '2001-01-01 00:00:00,000 fail2ban.actions [1]: NOTICE  [sshd] Ban 203.0.113.7',
        ]) + '\n')
        bans, ign = self.m.fail2ban_events(self.m.NOW - timedelta(hours=1))
        self.assertEqual([b['ip'] for b in bans], ['203.0.113.9'])
        self.assertEqual(ign[0]['ip'], '192.0.2.10')

    def test_nextcloud_both_formats(self):
        lines = [
            {'time': self.iso(5), 'remoteAddr': '192.0.2.10',
             'message': "Login failed: 'Administrator' (Remote IP: '192.0.2.10')"},
            {'time': self.iso(5), 'remoteAddr': '192.0.2.10',
             'message': 'Login failed: user@example.org (Remote IP: 192.0.2.10)'},
            {'time': self.iso(5), 'remoteAddr': '203.0.113.1',
             'message': 'Login failed: bob (Remote IP: 203.0.113.1)'},
        ]
        body = '\n'.join(json.dumps(x) for x in lines) + '\nnot json Login failed\n'
        self.m.OPT['NEXTCLOUD_LOG'] = self.write('nextcloud.log', body)
        hits, total = self.m.nextcloud_failed(self.m.NOW - timedelta(hours=1), self.wl)
        self.assertEqual(total, 3)
        self.assertEqual(sorted(h['detail'] for h in hits), ['user Administrator', 'user user@example.org'])

    def test_nextcloud_disabled(self):
        self.m.OPT['NEXTCLOUD_LOG'] = ''
        self.assertEqual(self.m.nextcloud_failed(self.m.NOW, self.wl), ([], None))


class TestReport(Base):
    def report(self, lang='en'):
        self.m.OPT['REPORT_LANG'] = lang
        self.m.OPT['REPORT_NAME'] = 'srv.example.org'
        wl = self.m.Whitelist()
        wl.add('192.0.2.10', 'allowlist offices', 'Rome <HQ>')
        t = self.m.NOW - timedelta(hours=1)
        bans = [
            dict(time=t, ip='203.0.113.5', what='crowdsecurity/ssh-bf', origin='CrowdSec', until=None, cn='NL', asn='AS1'),
            dict(time=t, ip='203.0.113.5', what='jail sshd', origin='fail2ban', until=None, cn='', asn=''),
            dict(time=t, ip='192.0.2.10', what='jail sshd', origin='fail2ban', until=None, cn='', asn=''),
        ]
        events = [dict(time=t, ip='192.0.2.10', kind='Nextcloud: failed login', detail='user bob')]
        return self.m.build(self.m.NOW - timedelta(hours=24), wl, bans, events, 4, {'CAPI': 10},
                            {'last_success': 'x', 'imported': '5', 'profile': 'standard', 'verified': 'yes'},
                            {'email_subject': 'Site - CrowdSec'})

    def test_subject_flags_banned_allowlisted_ip(self):
        subject, text, body = self.report()
        self.assertTrue(subject.startswith('[!! 1 allowlisted IPs BANNED] Site - CrowdSec - report'))
        self.assertIn(': 1 IPs banned', subject)           # the allowlisted IP is not counted as a normal ban
        self.assertIn('crowdsecurity/ssh-bf, jail sshd (fail2ban)', text)
        self.assertIn('Rome &lt;HQ&gt;', body)              # escaped
        self.assertLess(body.index('Allowlisted IPs involved'), body.index('Bans applied'))

    def test_italian(self):
        subject, text, body = self.report('it')
        self.assertIn('IP whitelist BANNATI', subject)
        self.assertIn('Ban applicati: 1 IP', text)
        self.assertIn('lang="it"', body)

    def test_empty_report(self):
        subject, text, body = self.m.build(self.m.NOW - timedelta(hours=24), self.m.Whitelist(), [], [], None, {}, {}, {})
        self.assertFalse(subject.startswith('['))
        self.assertIn('No events from allowlisted IPs', text)


class TestEndToEnd(Base):
    def test_dry_run_with_stub(self):
        stub = os.path.join(self.d, 'stub')
        os.makedirs(stub)
        os.environ['STUB_DIR'] = stub
        self.write('stub/allowlists.csv', 'name,description,created_at\noffices,Offices,2026-01-01\n')
        self.write('stub/allowlist-offices.csv',
                   'name,description,value,comment,expiration,created_at,console_managed\n'
                   'offices,Offices,192.0.2.10,Rome,never,2026-01-01,false\n'
                   'offices,Offices,192.0.2.11,old,2001-01-01T00:00:00Z,2001-01-01,false\n')
        self.write('stub/alerts-crowdsec.json', json.dumps([{
            'created_at': self.iso(30), 'scenario': 'crowdsecurity/http-probing',
            'stop_at': (self.m.NOW + timedelta(hours=3)).isoformat(),
            'source': {'cn': 'DE', 'as_name': 'Example AS'},
            'decisions': [{'origin': 'crowdsec', 'value': '203.0.113.20', 'scenario': 'crowdsecurity/http-probing'}]}]))
        self.write('stub/decisions.csv', 'id,source,ip\n1,CAPI,1.1.1.1\n2,crowdsec,203.0.113.20\n')
        conf = self.write('conf', '\n'.join([
            f'SMTP_CONF={self.write("email.yaml", EMAIL_YAML)}',
            f'CSCLI={os.path.join(ROOT, "tests", "stubs", "cscli")}',
            f'CROWDSEC_DIR={self.d}/cs', f'CROWDSEC_LOG_DIR={self.d}', 'FAIL2BAN_LOG=', 'NEXTCLOUD_LOG=',
            f'STATE_DIR={self.d}/state', f'BLOCKLIST_STATUS={self.d}/none']) + '\n')
        self.m.CONF = conf
        out = io.StringIO()
        with redirect_stdout(out):
            self.m.main(['--dry-run', '--since', '24h'])
        text = out.getvalue()
        self.assertIn('Subject: Site - CrowdSec - report', text)
        self.assertIn('203.0.113.20', text)
        self.assertIn('CAPI: 1', text)
        self.assertTrue(os.path.exists(os.path.join(self.d, 'state', 'preview.html')))
        self.assertFalse(os.path.exists(os.path.join(self.d, 'state', 'last_sent')))


if __name__ == '__main__':
    unittest.main()
