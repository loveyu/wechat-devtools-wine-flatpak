#include <X11/Xlib.h>
#include <X11/keysym.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef Bool (*fake_button_fn)(Display *, unsigned int, Bool, unsigned long);
typedef Bool (*fake_motion_fn)(Display *, int, int, int, unsigned long);
typedef Bool (*fake_key_fn)(Display *, unsigned int, Bool, unsigned long);

static int send_key(Display *display, fake_key_fn fake_key, KeySym symbol)
{
    KeyCode code = XKeysymToKeycode(display, symbol);
    if (!symbol || !code) return 0;
    fake_key(display, code, True, CurrentTime);
    usleep(35000);
    fake_key(display, code, False, CurrentTime);
    usleep(90000);
    return 1;
}

int main(int argc, char **argv)
{
    Display *display;
    void *xtst;
    fake_button_fn fake_button;
    fake_motion_fn fake_motion;
    fake_key_fn fake_key;

    if (argc < 3) {
        fprintf(stderr, "usage: %s click X Y | key KEYSYM | chord MOD KEY | text ASCII\n", argv[0]);
        return 64;
    }
    display = XOpenDisplay(NULL);
    if (!display) return 65;
    xtst = dlopen("libXtst.so.6", RTLD_NOW | RTLD_LOCAL);
    if (!xtst) return 66;
    fake_button = (fake_button_fn)dlsym(xtst, "XTestFakeButtonEvent");
    fake_motion = (fake_motion_fn)dlsym(xtst, "XTestFakeMotionEvent");
    fake_key = (fake_key_fn)dlsym(xtst, "XTestFakeKeyEvent");
    if (!fake_button || !fake_motion || !fake_key) return 67;

    if (!strcmp(argv[1], "click") && argc == 4) {
        fake_motion(display, DefaultScreen(display), atoi(argv[2]), atoi(argv[3]), CurrentTime);
        fake_button(display, 1, True, CurrentTime);
        fake_button(display, 1, False, CurrentTime);
    } else if (!strcmp(argv[1], "key") && argc == 3) {
        KeySym symbol = XStringToKeysym(argv[2]);
        if (!send_key(display, fake_key, symbol)) return 68;
    } else if (!strcmp(argv[1], "chord") && argc == 4) {
        KeySym modifier = XStringToKeysym(argv[2]);
        KeySym symbol = XStringToKeysym(argv[3]);
        KeyCode modifier_code = XKeysymToKeycode(display, modifier);
        if (!modifier || !modifier_code || !symbol) return 68;
        fake_key(display, modifier_code, True, CurrentTime);
        if (!send_key(display, fake_key, symbol)) return 68;
        fake_key(display, modifier_code, False, CurrentTime);
    } else if (!strcmp(argv[1], "text") && argc == 3) {
        size_t i;
        for (i = 0; argv[2][i]; ++i) {
            char key_name[2] = {argv[2][i], 0};
            if (!send_key(display, fake_key, XStringToKeysym(key_name))) return 68;
        }
    } else {
        return 64;
    }
    XFlush(display);
    usleep(300000);
    return 0;
}
