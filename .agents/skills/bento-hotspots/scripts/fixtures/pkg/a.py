from . import b


def chain(x):
    if x == 1:
        return "one"
    elif x == 2:
        return "two"
    elif x == 3:
        return "three"
    return "many"


def blocks(path, rows):
    with open(path) as fh:
        try:
            for row in rows:
                if row:
                    fh.write(row)
        except OSError:
            pass

    def inner(y):
        return y if y else None

    return inner


def dispatch(cmd):
    match cmd:
        case "go":
            while cmd:
                cmd = b.step(cmd)
        case _:
            pass
