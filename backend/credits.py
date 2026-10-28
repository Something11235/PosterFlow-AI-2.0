"""Exact website credit arithmetic. API boundaries serialize canonical decimals."""
from decimal import Decimal, InvalidOperation

PRECISION = Decimal('0.0001')


def credit_amount(value, *, allow_zero=True, limit=Decimal('100000')):
    if isinstance(value, bool) or value is None:
        raise ValueError('积分须为有效数字。')
    try:
        amount = Decimal(str(value))
        if not amount.is_finite() or amount.copy_abs() > limit or amount.quantize(PRECISION) != amount or (not allow_zero and amount == 0):
            raise ValueError('积分最多保留四位小数，且须在允许范围内。')
        return amount
    except (InvalidOperation, TypeError) as exc:
        raise ValueError('积分须为有效数字。') from exc


def credit_text(value):
    amount = credit_amount(value)
    return format(amount, 'f').rstrip('0').rstrip('.') if amount % 1 else str(int(amount))
