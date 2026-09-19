# ib_ops.py
from db_helpers import fetch_all


def get_full_log(conn, limit=100):
    """Полный журнал операций через функцию БД."""
    return fetch_all(conn, "SELECT * FROM asu_schema.f_get_logs(%s)", (limit,))
