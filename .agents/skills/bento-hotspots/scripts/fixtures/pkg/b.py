from pkg.a import chain


def step(cmd, a, b, c, d, e):
    return chain(cmd) and a or b


def late():
    from pkg import c  # deferred: breaks the cycle at runtime
    return c


from typing import TYPE_CHECKING  # noqa: E402

if TYPE_CHECKING:
    from pkg import c  # noqa: F811
