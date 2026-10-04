"""Pure reconciliation logic: match payments against bank statement entries by reference."""
from decimal import ROUND_HALF_UP, Decimal


def _to_paise(amount) -> Decimal:
    """Normalise an amount to two decimal places so 10.5 and 10.50 compare equal."""
    return Decimal(str(amount)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def _index(entries, label):
    index = {}
    for entry in entries:
        reference = entry["reference"]
        if reference in index:
            raise ValueError("duplicate reference in " + label + ": " + reference)
        index[reference] = _to_paise(entry["amount"])
    return index


def reconcile(payments, bank_entries) -> dict:
    """Compare payments with bank entries.

    Both arguments are lists of dicts with 'reference' and 'amount'.
    References must be unique within each list (ValueError otherwise).
    """
    payment_index = _index(payments, "payments")
    bank_index = _index(bank_entries, "bank_entries")

    matched = []
    mismatched = []
    for reference, amount in payment_index.items():
        if reference not in bank_index:
            continue
        if bank_index[reference] == amount:
            matched.append(reference)
        else:
            mismatched.append(
                {
                    "reference": reference,
                    "payment_amount": str(amount),
                    "bank_amount": str(bank_index[reference]),
                }
            )

    return {
        "matched": sorted(matched),
        "amount_mismatch": sorted(mismatched, key=lambda item: item["reference"]),
        "missing_in_bank": sorted(set(payment_index) - set(bank_index)),
        "unexpected_in_bank": sorted(set(bank_index) - set(payment_index)),
    }
