"""Offline auth integration checks; all credentials are synthetic."""
import os
import unittest
from unittest.mock import patch
from fastapi.testclient import TestClient
from ai.owner_session import issue_owner_session, verify_owner_session
from ai.server import app, _recent, owner_autopatch_enabled
from types import SimpleNamespace

class OwnerSessionTests(unittest.TestCase):
    def setUp(self):
        _recent.clear()
        self.env = patch.dict(os.environ, {
            'WHITEAI_ADMIN_KEY': 'a' * 40, 'WHITEAI_INGEST_KEY': 'i' * 24,
            'WHITEAI_SESSION_NOT_BEFORE': '0', 'WHITEAI_AUTOPATCH_ENABLED': '1',
            'GITHUB_TOKEN': 'offline', 'GEMINI_API_KEY': 'offline'}, clear=True)
        self.env.start()
        self.addCleanup(self.env.stop)
        self.client = TestClient(app)

    def pair(self):
        r = self.client.post('/auth/pair', headers={'X-WhiteAI-Admin-Key': 'a' * 40})
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.headers['cache-control'], 'no-store')
        self.assertNotIn('a' * 40, r.text)
        return r.json()['session_token']

    def test_pair_recover_reports_jobs_and_autopatch(self):
        token = self.pair()
        headers = {'X-WhiteAI-Session': token}
        self.assertEqual(self.client.get('/auth/session', headers=headers).status_code, 200)
        self.assertTrue(owner_autopatch_enabled(SimpleNamespace(headers=headers)))
        r = self.client.post('/reports', headers=headers, json={
            'category': 'manual_diagnostic', 'reason': 'Offline manual review'})
        self.assertEqual(r.status_code, 202)
        self.assertEqual(self.client.get('/jobs/' + r.json()['job_id'], headers=headers).status_code, 200)
        with patch.dict(os.environ, {'WHITEAI_AUTOPATCH_ENABLED': '0'}):
            self.assertFalse(owner_autopatch_enabled(SimpleNamespace(headers=headers)))

    def test_wrong_master_missing_session_and_throttle(self):
        self.assertEqual(self.client.post('/auth/pair', headers={'X-WhiteAI-Admin-Key': 'wrong'}).status_code, 403)
        self.assertEqual(self.client.post('/auth/pair').status_code, 429)
        self.assertEqual(self.client.get('/auth/session').status_code, 401)
        self.assertEqual(self.client.post('/reports', json={}).status_code, 401)

    def test_expiry_tampering_rotation_cutoff_and_restart(self):
        token, expires = issue_owner_session('a' * 40, now=1000)
        self.assertTrue(verify_owner_session(token, 'a' * 40, now=1001))
        for bad in (token[:-1] + ('0' if token[-1] != '0' else '1'), '', 'wa1.bad', 'x'*257):
            self.assertFalse(verify_owner_session(bad, 'a' * 40, now=1001))
        self.assertFalse(verify_owner_session(token, 'a' * 40, now=expires))
        self.assertFalse(verify_owner_session(token, 'b' * 40, now=1001))
        self.assertFalse(verify_owner_session(token, 'a' * 40, now=1001, not_before=1001))
        live = self.pair()
        _recent.clear()  # no session registry needed after restart
        self.assertEqual(self.client.get('/auth/session', headers={'X-WhiteAI-Session': live}).status_code, 200)
        with patch.dict(os.environ, {'WHITEAI_SESSION_NOT_BEFORE': 'invalid'}):
            self.assertEqual(self.client.get('/auth/session', headers={'X-WhiteAI-Session': live}).status_code, 401)

    def test_unconfigured_pairing_and_revoked_session_fail_closed(self):
        token = self.pair()
        with patch.dict(os.environ, {'WHITEAI_ADMIN_KEY': 'b' * 40}):
            headers = {'X-WhiteAI-Session': token}
            self.assertEqual(self.client.get('/auth/session', headers=headers).status_code, 401)
            self.assertEqual(self.client.post('/reports', headers=headers, json={}).status_code, 401)
        _recent.clear()
        with patch.dict(os.environ, {'WHITEAI_ADMIN_KEY': ''}):
            self.assertEqual(self.client.post('/auth/pair').status_code, 503)
        _recent.clear()
        self.assertEqual(self.client.post('/auth/pair', headers={'X-WhiteAI-Admin-Key': 'wrong'}).status_code, 403)

    def test_ingestion_cannot_pair_or_authorize_autopatch(self):
        h = {'X-WhiteAI-Key': 'i' * 24}
        self.assertEqual(self.client.post('/auth/pair', headers=h).status_code, 403)
        self.assertFalse(owner_autopatch_enabled(SimpleNamespace(headers=h)))
        self.assertEqual(self.client.get('/jobs/missing', headers=h).status_code, 404)
        self.assertEqual(self.client.get('/jobs/missing', headers={**h, 'X-WhiteAI-Session': 'invalid'}).status_code, 401)

if __name__ == '__main__':
    unittest.main()
