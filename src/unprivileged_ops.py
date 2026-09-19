# unprivileged_ops.py
from db_helpers import fetch_all


def get_public_params(conn):
    """Общедоступные параметры через функцию БД."""
    return fetch_all(
        conn,
        "SELECT object_name, current_value, unit, location FROM asu_schema.f_get_public_params()"
    )
