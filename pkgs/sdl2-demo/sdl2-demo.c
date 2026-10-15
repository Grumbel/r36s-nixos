/*
 * Minimal SDL2 demo for the R36S: accelerated rendering, audio and
 * gamepad input.
 *
 * - Left stick / D-pad moves the white square, right stick the red one
 * - Every button plays a note
 * - Start + Select (or Escape, or the time given as first argument in
 *   seconds) quits
 */
#include <SDL.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#define SAMPLE_RATE 48000

/* Shared with the audio callback, protected by SDL_LockAudioDevice() */
static double tone_freq = 0.0;
static int tone_samples_left = 0;
static double tone_phase = 0.0;

static void audio_callback(void *userdata, Uint8 *stream, int len)
{
	Sint16 *out = (Sint16 *)stream;
	int frames = len / (2 * sizeof(Sint16));

	(void)userdata;
	for (int i = 0; i < frames; i++) {
		Sint16 s = 0;

		if (tone_samples_left > 0) {
			/* Sine with a short linear fade out */
			double env = tone_samples_left < 2400 ? tone_samples_left / 2400.0 : 1.0;

			s = (Sint16)(sin(tone_phase) * 8000.0 * env);
			tone_phase += 2.0 * M_PI * tone_freq / SAMPLE_RATE;
			if (tone_phase > 2.0 * M_PI)
				tone_phase -= 2.0 * M_PI;
			tone_samples_left--;
		}
		out[2 * i] = s;
		out[2 * i + 1] = s;
	}
}

static void play_note(SDL_AudioDeviceID dev, int note)
{
	SDL_LockAudioDevice(dev);
	/* A major pentatonic, starting at A4 */
	static const int steps[] = { 0, 2, 4, 7, 9 };
	int semitones = steps[note % 5] + 12 * ((note / 5) % 3);
	tone_freq = 440.0 * pow(2.0, semitones / 12.0);
	tone_samples_left = SAMPLE_RATE / 4;
	SDL_UnlockAudioDevice(dev);
}

static float axis_value(SDL_Joystick *joy, int axis)
{
	if (!joy || axis >= SDL_JoystickNumAxes(joy))
		return 0.0f;
	float v = SDL_JoystickGetAxis(joy, axis) / 32767.0f;
	return fabsf(v) < 0.15f ? 0.0f : v;
}

int main(int argc, char *argv[])
{
	double timeout = argc > 1 ? atof(argv[1]) : 0.0;

	if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_JOYSTICK) != 0) {
		fprintf(stderr, "SDL_Init: %s\n", SDL_GetError());
		return 1;
	}

	printf("video driver: %s\n", SDL_GetCurrentVideoDriver());
	printf("audio driver: %s\n", SDL_GetCurrentAudioDriver());

	SDL_Window *win = SDL_CreateWindow("sdl2-demo", SDL_WINDOWPOS_UNDEFINED,
					   SDL_WINDOWPOS_UNDEFINED, 0, 0,
					   SDL_WINDOW_FULLSCREEN_DESKTOP);
	if (!win) {
		fprintf(stderr, "SDL_CreateWindow: %s\n", SDL_GetError());
		return 1;
	}

	SDL_Renderer *ren = SDL_CreateRenderer(win, -1, SDL_RENDERER_ACCELERATED |
						     SDL_RENDERER_PRESENTVSYNC);
	if (!ren) {
		fprintf(stderr, "SDL_CreateRenderer: %s\n", SDL_GetError());
		return 1;
	}

	SDL_RendererInfo info;
	SDL_GetRendererInfo(ren, &info);
	int w, h;
	SDL_GetRendererOutputSize(ren, &w, &h);
	printf("renderer: %s, %dx%d\n", info.name, w, h);

	SDL_AudioSpec want = { 0 }, have;
	want.freq = SAMPLE_RATE;
	want.format = AUDIO_S16SYS;
	want.channels = 2;
	want.samples = 512;
	want.callback = audio_callback;
	SDL_AudioDeviceID adev = SDL_OpenAudioDevice(NULL, 0, &want, &have, 0);
	if (adev)
		SDL_PauseAudioDevice(adev, 0);
	else
		fprintf(stderr, "SDL_OpenAudioDevice: %s\n", SDL_GetError());

	/* The R36S has two input devices: gpio-keys (buttons) and
	 * adc-joystick (sticks) */
	SDL_Joystick *sticks = NULL;
	for (int i = 0; i < SDL_NumJoysticks(); i++) {
		SDL_Joystick *joy = SDL_JoystickOpen(i);
		if (!joy)
			continue;
		printf("joystick %d: %s, %d axes, %d buttons\n", i, SDL_JoystickName(joy),
		       SDL_JoystickNumAxes(joy), SDL_JoystickNumButtons(joy));
		if (!sticks && SDL_JoystickNumAxes(joy) >= 4)
			sticks = joy;
	}

	SDL_ShowCursor(SDL_DISABLE);
	if (adev)
		play_note(adev, 0);

	float px = w / 3.0f, py = h / 2.0f;
	float qx = 2 * w / 3.0f, qy = h / 2.0f;
	int dpad_x = 0, dpad_y = 0;
	int start = 0, select = 0;
	Uint64 t0 = SDL_GetPerformanceCounter(), last_fps = t0, prev = t0;
	int frames = 0, running = 1;

	while (running) {
		SDL_Event ev;
		while (SDL_PollEvent(&ev)) {
			switch (ev.type) {
			case SDL_QUIT:
				running = 0;
				break;
			case SDL_KEYDOWN:
				if (ev.key.keysym.sym == SDLK_ESCAPE)
					running = 0;
				break;
			case SDL_JOYBUTTONDOWN:
			case SDL_JOYBUTTONUP: {
				int down = ev.type == SDL_JOYBUTTONDOWN;
				SDL_Joystick *joy = SDL_JoystickFromInstanceID(ev.jbutton.which);
				const char *name = joy ? SDL_JoystickName(joy) : "?";

				if (down)
					printf("button %d down (%s)\n", ev.jbutton.button, name);
				/* gpio-keys button order follows the key codes:
				 * B, A, X, Y, L1, R1, L2, R2, Select, Start, FN,
				 * L3, R3, then the D-pad */
				switch (ev.jbutton.button) {
				case 8: select = down; break;
				case 9: start = down; break;
				case 13: dpad_y = down ? -1 : 0; break;
				case 14: dpad_y = down ? 1 : 0; break;
				case 15: dpad_x = down ? -1 : 0; break;
				case 16: dpad_x = down ? 1 : 0; break;
				}
				if (down && adev)
					play_note(adev, ev.jbutton.button);
				if (start && select)
					running = 0;
				break;
			}
			}
		}

		Uint64 now = SDL_GetPerformanceCounter();
		double dt = (double)(now - prev) / SDL_GetPerformanceFrequency();
		double t = (double)(now - t0) / SDL_GetPerformanceFrequency();
		prev = now;
		if (timeout > 0 && t > timeout)
			running = 0;

		float speed = 300.0f * (float)dt;
		px += (axis_value(sticks, 0) + dpad_x) * speed;
		py += (axis_value(sticks, 1) + dpad_y) * speed;
		qx += axis_value(sticks, 2) * speed;
		qy += axis_value(sticks, 3) * speed;
		px = SDL_clamp(px, 0, w); py = SDL_clamp(py, 0, h);
		qx = SDL_clamp(qx, 0, w); qy = SDL_clamp(qy, 0, h);

		/* Slowly cycling background */
		SDL_SetRenderDrawColor(ren, (Uint8)(40 + 30 * sin(t * 0.7)),
				       (Uint8)(40 + 30 * sin(t * 0.9 + 2)),
				       (Uint8)(60 + 40 * sin(t * 1.1 + 4)), 255);
		SDL_RenderClear(ren);

		/* A ring of rotating, color cycling squares */
		for (int i = 0; i < 24; i++) {
			double a = t + i * 2.0 * M_PI / 24;
			double r = h * 0.35 * (1.0 + 0.15 * sin(t * 2 + i));
			SDL_Rect rc = { (int)(w / 2 + cos(a) * r) - 10, (int)(h / 2 + sin(a) * r) - 10, 20, 20 };
			SDL_SetRenderDrawColor(ren, (Uint8)(128 + 127 * sin(a)),
					       (Uint8)(128 + 127 * sin(a + 2)),
					       (Uint8)(128 + 127 * sin(a + 4)), 255);
			SDL_RenderFillRect(ren, &rc);
		}

		SDL_Rect p = { (int)px - 16, (int)py - 16, 32, 32 };
		SDL_SetRenderDrawColor(ren, 255, 255, 255, 255);
		SDL_RenderFillRect(ren, &p);
		SDL_Rect q = { (int)qx - 16, (int)qy - 16, 32, 32 };
		SDL_SetRenderDrawColor(ren, 255, 60, 60, 255);
		SDL_RenderFillRect(ren, &q);

		SDL_RenderPresent(ren);

		frames++;
		if (now - last_fps >= SDL_GetPerformanceFrequency()) {
			printf("fps: %d\n", frames);
			fflush(stdout);
			frames = 0;
			last_fps = now;
		}
	}

	if (adev)
		SDL_CloseAudioDevice(adev);
	SDL_DestroyRenderer(ren);
	SDL_DestroyWindow(win);
	SDL_Quit();
	return 0;
}
