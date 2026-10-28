import copy
import unittest
from unittest.mock import Mock, patch
from types import SimpleNamespace

from backend import image_delivery, server

OWNER='user-11111111-1111-4111-8111-111111111111'
TASK='task_owned_image'

class ImageDeliverySourceTests(unittest.TestCase):
    def setUp(self):
        self.gateway=Mock()
        self.job={'owner_scope':OWNER,'billing_mode':'platform','status':'completed','provider_task_id':TASK,'image_keys':['one.png','two.png']}
        self.gateway._request.return_value=[self.job]
        self.payload={'data':{'id':TASK,'status':'completed','result':{'images':[{'url':['https://upload.apimart.ai/one.png'],'expires_at':1800},{'url':['https://upload.apimart.ai/two.png'],'expires_at':1200}]}}}

    def source(self,filename='two.png',owner=OWNER,key='fixture'):
        with patch.object(image_delivery.provider,'api_request',return_value=self.payload) as remote:
            value=image_delivery.preferred_original(self.gateway,owner,filename,key,now=1000)
        return value,remote

    def test_owned_platform_exact_index_expiry_and_read_only_query(self):
        value,remote=self.source()
        self.assertEqual(value,{'url':'https://upload.apimart.ai/two.png','expires_in':170,'variant':'original','source':'upstream'})
        self.assertEqual(remote.call_args.args,('GET','/tasks/'+TASK+'?language=zh','fixture'))
        self.assertEqual(remote.call_args.kwargs['timeout'],(2,3))
        method,path=self.gateway._request.call_args.args;self.assertEqual(method,'GET')
        p=self.gateway._request.call_args.kwargs['params'];self.assertEqual(p['owner_scope'],'eq.'+OWNER);self.assertEqual(p['image_keys'],'cs.["two.png"]');self.assertEqual(p['billing_mode'],'eq.platform')

    def test_no_key_or_guest_or_invalid_filename_never_queries(self):
        for owner,key,name in [(OWNER,'','one.png'),('guest-fixture','fixture','one.png'),(OWNER,'fixture','../one.png')]:
            self.gateway.reset_mock();value,remote=self.source(name,owner,key);self.assertIsNone(value);remote.assert_not_called();self.gateway._request.assert_not_called()

    def test_foreign_own_key_incomplete_or_unmatched_job_never_queries_provider(self):
        for change in [{'owner_scope':'user-other'},{'billing_mode':'own_key'},{'status':'saving'},{'image_keys':['foreign.png']},{'provider_task_id':'bad/task'}]:
            self.gateway._request.return_value=[{**self.job,**change}];value,remote=self.source();self.assertIsNone(value);remote.assert_not_called()

    def test_expired_unknown_or_mismatched_task_falls_back(self):
        for expiry in [None,1000,1025,'bad',float('inf'),True]:
            self.payload['data']['result']['images'][1]['expires_at']=expiry;self.assertIsNone(self.source()[0])
        self.payload['data']['result']['images'][1]['expires_at']=1500
        for change in [{'id':'task_someone_else'},{'status':'processing'},{'result':{'images':[]}}]:
            original=copy.deepcopy(self.payload);self.payload['data'].update(change);self.assertIsNone(self.source()[0]);self.payload=original

    def test_unsafe_or_unrecognized_media_url_falls_back(self):
        for url in ['http://upload.apimart.ai/a','https://127.0.0.1/a','https://upload.apimart.ai.evil.example/a','https://key@upload.apimart.ai/a','https://upload.apimart.ai:bad/a','https://upload.apimart.ai/a#secret','https://upload.apimart.ai/a\n','https://upload.apimart.ai/a?api_key=fixture']:
            self.payload['data']['result']['images'][1]['url']=[url];self.assertIsNone(self.source()[0])

    def test_explicit_backup_and_thumbnails_skip_upstream_and_preserve_signing(self):
        client=server.app.test_client()
        with patch.object(server,'set_optional_storage_scope'),patch.object(server,'_storage_backend',return_value='supabase'),patch.object(server,'_supabase_create_signed_url',return_value='https://backup.example/test.png'),patch.object(image_delivery,'preferred_original') as preferred:
            for suffix in ['?source=backup','?variant=thumbnail']:
                response=client.get('/api/images/one.png/url'+suffix);self.assertEqual(response.status_code,200);self.assertEqual(response.json['url'],'https://backup.example/test.png')
            preferred.assert_not_called()

    def test_provider_or_lookup_failure_returns_backup_without_mutating_tasks(self):
        client=server.app.test_client()
        with patch.object(server,'optional_authenticated_user',return_value=SimpleNamespace(id=OWNER.removeprefix('user-'))),patch.object(server,'SupabaseGateway',return_value=self.gateway),patch.object(server,'_storage_backend',return_value='supabase'),patch.object(server,'_supabase_create_signed_url',return_value='https://backup.example/test.png'),patch.object(image_delivery,'preferred_original',side_effect=RuntimeError('secret internal details')):
            r=client.get('/api/images/one.png/url');self.assertEqual(r.status_code,200);self.assertEqual(r.json['url'],'https://backup.example/test.png');self.assertNotIn('secret',r.get_data(as_text=True))

    def test_client_identifier_cannot_impersonate_an_account_namespace(self):
        for header in ['X-Client-Id','x-client-id']:
            with server.app.test_request_context(headers={header:OWNER}):
                self.assertNotEqual(server.storage_scope_name(),OWNER)
        with server.app.test_request_context('/api/images/one.png?client_id='+OWNER):
            self.assertNotEqual(server.storage_scope_name(),OWNER)

    def test_anonymous_spoofed_owner_never_queries_upstream_or_signs_account_path(self):
        with patch.object(server,'optional_authenticated_user',return_value=None),patch.object(server,'_storage_backend',return_value='supabase'),patch.object(server,'_supabase_create_signed_url',return_value='https://backup.example/test.png') as sign,patch.object(image_delivery,'preferred_original') as preferred:
            r=server.app.test_client().get('/api/images/one.png/url',headers={'X-Client-Id':OWNER});self.assertEqual(r.status_code,200)
            preferred.assert_not_called();self.assertNotIn(OWNER,sign.call_args.args[0])

    def test_authenticated_owner_controls_upstream_lookup_not_client_header(self):
        expected={'url':'https://upload.apimart.ai/one.png','expires_in':120,'variant':'original','source':'upstream'}
        with patch.object(server,'optional_authenticated_user',return_value=SimpleNamespace(id=OWNER.removeprefix('user-'))),patch.object(server,'SupabaseGateway',return_value=self.gateway),patch.object(server,'_storage_backend',return_value='supabase'),patch.object(server,'_supabase_create_signed_url') as sign,patch.object(image_delivery,'preferred_original',return_value=expected) as preferred:
            r=server.app.test_client().get('/api/images/one.png/url',headers={'X-Client-Id':'user-other-account'});self.assertEqual(r.status_code,200);self.assertEqual(r.json['source'],'upstream')
            self.assertEqual(preferred.call_args.args[1],OWNER);sign.assert_not_called()
