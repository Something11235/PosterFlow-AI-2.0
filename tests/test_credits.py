import unittest
from decimal import Decimal
from backend.credits import credit_amount, credit_text


class CreditPrecisionTests(unittest.TestCase):
    def test_exact_fractional_values_and_canonical_boundary(self):
        self.assertEqual(credit_amount('0.1')+credit_amount('0.2'), Decimal('0.3'))
        for raw, expected in [('10.0000','10'),('0.5000','0.5'),('-0.0001','-0.0001'),('0','0')]:
            self.assertEqual(credit_text(raw),expected)
        self.assertEqual(credit_amount('0.5')*Decimal('15.123'), Decimal('7.5615'))

    def test_invalid_or_overprecise_values_are_never_silently_rounded(self):
        for raw in [None,True,False,'NaN','Infinity','-Infinity','0.00001','100000.0001','not a number']:
            with self.subTest(raw=raw),self.assertRaises(ValueError):credit_amount(raw)
        with self.assertRaises(ValueError):credit_amount(0,allow_zero=False)
