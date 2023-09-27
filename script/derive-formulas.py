from sympy import Symbol, simplify, solve
from sympy.abc import a, b, s, v


def buffer_to_rel(b, x):
    return b / x


def rel_to_buffer(r, x):
    return r * x


def main():
    dx = Symbol('dx')
    x0 = Symbol('x0')
    l0 = Symbol('l0')
    b0 = rel_to_buffer(l0, x0)

    x1 = x0 + dx
    b1 = b0 + dx

    l1 = Symbol('l1')

    res = solve(
        [
            l1 - buffer_to_rel(b1, x1),
        ],
        (l1)
    )
    print(f'res: {res}')


if __name__ == '__main__':
    main()
