# utils.py
import os
import sys


def clear_screen():
    if sys.platform == 'win32':
        os.system('cls')
    else:
        os.system('clear')


def print_header(title):
    clear_screen()
    print("=" * 60)
    print("{:^60}".format(title))
    print("=" * 60)


def wait_for_enter():
    input("\nНажмите Enter для продолжения...")


def format_value(value, unit=""):
    if value is None:
        return "Н/Д"
    if isinstance(value, float):
        value_text = "{:.2f}".format(value)
        value_text = value_text.rstrip('0').rstrip('.')
    else:
        value_text = str(value)
    if unit:
        return "{} {}".format(value_text, unit)
    return value_text


def format_datetime(dt):
    if dt is None:
        return "Н/Д"
    try:
        return dt.strftime("%Y-%m-%d %H:%M:%S")
    except Exception:
        return str(dt)


def bool_ru(value):
    return "Да" if value else "Нет"


def status_ru(value):
    return "Успешно" if value else "Ошибка"


def safe_text(value, max_len=None):
    if value is None:
        text = ""
    else:
        text = str(value)
    text = text.replace('\n', ' ').replace('\r', ' ')
    if max_len is not None and len(text) > max_len:
        return text[:max_len - 3] + "..."
    return text
