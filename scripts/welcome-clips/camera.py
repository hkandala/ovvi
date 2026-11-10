#!/usr/bin/env python3
"""The camera of a welcome clip: ffmpeg's zoompan expressions for a push-in that follows the action.

Usage: camera.py <width>x<height> <t:zoom:cx:cy>... prints the zoompan filter. Each key is a time in seconds, a zoom (1
shows the whole film) and the centre the camera looks at, as fractions of the film. Between two keys the camera moves
as a critically damped spring (no overshoot) that settles by the next key."""
import sys


def spring(a, b, t0, t1):
    # 1 - (1 + w) e^-w, w from 0 to 7.4: the step response of a critically damped spring, scaled to land on b at t1.
    w = f"(7.4*clip((it-{t0})/{t1 - t0},0,1))"
    return f"({a}+({b - a})*(1-(1+{w})*exp(-{w}))/0.99487)"


def path(keys, index):
    expression = str(keys[-1][index])
    for (t0, *a), (t1, *b) in reversed(list(zip(keys, keys[1:]))):
        expression = f"if(lt(it,{t1}),{spring(a[index - 1], b[index - 1], t0, t1)},{expression})"
    return expression


size = sys.argv[1]
keys = [tuple(float(n) for n in key.split(":")) for key in sys.argv[2:]] or [(0, 1, 0.5, 0.5)]
z, cx, cy = path(keys, 1), path(keys, 2), path(keys, 3)
# The film's own frames, one out per frame in (d=1); x and y keep the view inside the film.
print(f"zoompan=d=1:s={size}:fps=60:z='{z}':x='clip({cx}*iw-iw/zoom/2,0,iw-iw/zoom)'"
      f":y='clip({cy}*ih-ih/zoom/2,0,ih-ih/zoom)'")
