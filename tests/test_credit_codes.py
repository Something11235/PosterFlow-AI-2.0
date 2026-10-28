import json
import unittest
from types import SimpleNamespace
from unittest.mock import Mock,patch
from flask import Flask,jsonify
from cryptography.fernet import Fernet
from backend import credit_codes as c

RID='11111111-1111-4111-8111-111111111111'
UID='22222222-2222-4222-8222-222222222222'


class CreditCodeTests(unittest.TestCase):
    def setUp(self):
        self.secret=patch.dict(c.os.environ,{'SUPABASE_SERVICE_ROLE_KEY':'offline-credit-code-server-secret'});self.secret.start();self.addCleanup(self.secret.stop)
        self.gateway=Mock();self.user=SimpleNamespace(id=UID);self.require_user=Mock(return_value=self.user);self.require_admin=Mock(return_value=(self.user,self.gateway))
        app=Flask(__name__);app.register_blueprint(c.create_credit_code_blueprint(self.require_user,self.require_admin,Mock(),[],lambda e:(jsonify(code=e.code,error=e.message),e.status)))
        self.client=app.test_client()

    def params(self,**extra):return {'request_id':RID,'package_id':'pf20','quantity':5,'note':'fixture',**extra}

    def test_crypto_random_unique_safe_single_lines_and_database_has_only_proofs_and_ciphertext(self):
        batch=c.new_batch(self.params(quantity=500));codes=json.loads(c.export_cipher().decrypt(batch['p_export'].encode()))
        self.assertEqual(len(codes),500);self.assertEqual(len(set(codes)),500)
        self.assertTrue(all(c.CODE.fullmatch(code) and len(code)<=30 for code in codes))
        self.assertEqual([c.code_hash(x) for x in codes],[v['hash'] for v in batch['p_codes']])
        self.assertTrue(all(code not in json.dumps(batch) for code in codes))
        self.assertEqual(c.normalize_code(' '+codes[0].lower()[:10]+'-\n'+codes[0].lower()[10:]+' '),codes[0])
        other=c.new_batch(self.params());self.assertEqual(other['p_fingerprint'],c.new_batch(self.params())['p_fingerprint']);self.assertNotEqual(batch['p_export'],other['p_export'])

    def test_request_cannot_supply_arbitrary_credits_keys_or_invalid_batches(self):
        for extra in [{'credits':100000},{'quantity':True},{'quantity':0},{'quantity':501},{'package_id':'made-up'},{'note':'x'*241},{'request_id':'bad'}]:
            with self.subTest(extra=extra),self.assertRaises(c.CreditCodeError):c.new_batch(self.params(**extra))

    def test_user_redeem_never_sends_cleartext_to_rpc_and_enforces_origin(self):
        batch=c.new_batch(self.params());code=json.loads(c.export_cipher().decrypt(batch['p_export'].encode()))[0]
        with patch.object(c,'SupabaseGateway',return_value=self.gateway):
            self.gateway.rpc.return_value={'ok':True,'credits':20,'balance':30,'idempotent':False}
            response=self.client.post('/api/credit-codes/redeem',json={'code':code})
            self.assertEqual(response.status_code,200);self.assertEqual(response.json['credits'],20)
            self.assertEqual(self.gateway.rpc.call_args.args,('redeem_credit_code',{'p_user_id':UID,'p_hash':c.code_hash(code)}))
            self.assertNotIn(code,json.dumps(response.json));self.assertEqual(response.headers['Cache-Control'],'private, no-store')
            self.gateway.rpc.reset_mock();self.assertEqual(self.client.post('/api/credit-codes/redeem',json={'code':code},headers={'Origin':'https://attacker.invalid'}).status_code,403);self.gateway.rpc.assert_not_called()

    def test_invalid_proofs_count_persistent_attempts_without_echo_and_cross_account_is_generic(self):
        with patch.object(c,'SupabaseGateway',return_value=self.gateway):
            for error,status in [('CREDIT_CODE_UNAVAILABLE',400),('CREDIT_CODE_RATE_LIMIT',429),('EMAIL_UNVERIFIED',403),('ACCOUNT_FROZEN',403)]:
                self.gateway.rpc.return_value={'ok':False,'code':error}
                response=self.client.post('/api/credit-codes/redeem',json={'code':'sensitive invalid value'})
                self.assertEqual(response.status_code,status);self.assertNotIn('sensitive',response.get_data(as_text=True));self.assertEqual(self.gateway.rpc.call_args.args[1]['p_hash'],'')

    def test_admin_batch_reply_is_metadata_only_and_download_filters_redeemed_codes(self):
        self.gateway.rpc.return_value={'ok':True,'existing':False,'batch':{'id':RID,'quantity':5,'credits':20}}
        response=self.client.post('/api/credit-codes/admin/batches',json=self.params());self.assertEqual(response.status_code,201)
        args=self.gateway.rpc.call_args.args[1];self.assertEqual(args['p_admin'],UID)
        codes=json.loads(c.export_cipher().decrypt(args['p_export'].encode()))
        self.assertTrue(all(code not in response.get_data(as_text=True) for code in codes))
        self.gateway.rpc.return_value={'ok':True,'package_id':'pf20','encrypted_export':args['p_export'],'ready_hashes':[c.code_hash(codes[0])]}
        response=self.client.post('/api/credit-codes/admin/batches/'+RID+'/export',json={})
        self.assertEqual(response.status_code,200);self.assertEqual(response.json['text'],codes[0]);self.assertEqual(response.json['count'],1)
        self.assertEqual(response.headers['Cache-Control'],'private, no-store')

    def test_wrong_or_rotated_export_key_never_leaks_cipher_or_tokens(self):
        batch=c.new_batch(self.params());self.gateway.rpc.return_value={'ok':True,'package_id':'pf20','encrypted_export':batch['p_export'],'ready_hashes':[]}
        with patch.dict(c.os.environ,{'SUPABASE_SERVICE_ROLE_KEY':'different-server-export-key'}):
            response=self.client.post('/api/credit-codes/admin/batches/'+RID+'/export',json={})
        self.assertEqual(response.status_code,503);self.assertNotIn(batch['p_export'],response.get_data(as_text=True))

    def test_no_admin_or_no_login_cannot_mint_export_void_or_redeem(self):
        self.require_admin.side_effect=c.CreditCodeError('ADMIN_REQUIRED','fixture',403)
        for path,body in [('/admin/batches',self.params()),('/admin/batches/'+RID+'/export',{}),('/admin/batches/'+RID+'/void',{'reason':'fixture'}),('/admin/cards/void',{'code':'x','reason':'fixture'})]:
            self.assertEqual(self.client.post('/api/credit-codes'+path,json=body).status_code,403)
        self.gateway.rpc.assert_not_called();self.require_user.side_effect=c.CreditCodeError('AUTH_REQUIRED','fixture',401)
        self.assertEqual(self.client.post('/api/credit-codes/redeem',json={'code':'x'}).status_code,401)

    def test_single_code_void_hashes_input_and_preserves_already_redeemed_error(self):
        batch=c.new_batch(self.params());code=json.loads(c.export_cipher().decrypt(batch['p_export'].encode()))[0]
        self.gateway.rpc.return_value={'ok':True,'voided':1}
        response=self.client.post('/api/credit-codes/admin/cards/void',json={'code':code,'reason':'未用码退款'})
        self.assertEqual(response.status_code,200)
        self.assertEqual(self.gateway.rpc.call_args.args,('void_credit_code',{'p_admin':UID,'p_hash':c.code_hash(code),'p_reason':'未用码退款'}))
        self.assertNotIn(code,response.get_data(as_text=True))
        self.gateway.rpc.return_value={'ok':False,'code':'CREDIT_CODE_ALREADY_REDEEMED'}
        response=self.client.post('/api/credit-codes/admin/cards/void',json={'code':code,'reason':'已用码售后'})
        self.assertEqual(response.status_code,409)

    def test_config_and_histories_do_not_claim_automatic_taobao_verification(self):
        with patch.object(c,'is_supabase_configured',return_value=False):response=self.client.get('/api/credit-codes/config')
        self.assertFalse(response.json['ready']);self.assertFalse(response.json['automatic_taobao_verification']);self.assertEqual(len(response.json['packages']),5)
        self.assertEqual(response.json['purchase_url'],c.PURCHASE_URL)
