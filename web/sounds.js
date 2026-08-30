/*
 * Positional audio for mi_fire.
 *
 * Web Audio rather than <audio> elements, for one reason: StereoPannerNode. An <audio>
 * tag can be made quieter with distance but cannot be placed left or right, and bearing is
 * most of what makes a sound feel located. When you are hunting a PASS alarm in a smoke
 * filled building, the pan is the cue you actually use.
 *
 * What this cannot do is occlusion. A PASS through a wall sounds exactly like one in the
 * open, and real muffling is a genuine search cue. Fixing that needs a GTA audio pack
 * (.awc + .dat54.rel) driven by the engine, which is the eventual answer -- at which point
 * this file stops being used and nothing else changes.
 *
 * Lua sends volume and pan already computed, because it is the side that knows where the
 * camera is pointing.
 */

(() => {
    'use strict';

    /** @type {AudioContext | null} */
    let ctx = null;

    /** Decoded buffers, keyed by file path. Fetched once. */
    const buffers = new Map();

    /** Files that failed to load, so a missing sound is not retried forever. */
    const failed = new Set();

    /** Live sources, keyed by the id Lua gave us (a player server id). */
    const playing = new Map();

    // -----------------------------------------------------------------------

    /**
     * The AudioContext often starts suspended until the page sees interaction. NUI has no
     * interaction, so resume it explicitly and keep trying on each message rather than
     * assuming the first attempt worked.
     */
    function audioContext() {
        if (!ctx) {
            const Ctor = window.AudioContext || window.webkitAudioContext;
            if (!Ctor) return null;
            ctx = new Ctor();
        }
        if (ctx.state === 'suspended') ctx.resume().catch(() => {});
        return ctx;
    }

    /**
     * Fetch and decode a file, once. Returns null while loading or if it failed, and the
     * caller simply plays nothing -- a missing sound should never throw.
     * @param {string} file
     * @returns {AudioBuffer | null}
     */
    function bufferFor(file) {
        if (buffers.has(file)) return buffers.get(file);
        if (failed.has(file)) return null;

        // Mark as in-flight so a message every 200ms does not start a fetch every 200ms.
        failed.add(file);

        fetch(file)
            .then((response) => {
                if (!response.ok) throw new Error(`${response.status} ${response.statusText}`);
                return response.arrayBuffer();
            })
            .then((data) => {
                const context = audioContext();
                if (!context) throw new Error('no AudioContext');
                return context.decodeAudioData(data);
            })
            .then((decoded) => {
                buffers.set(file, decoded);
                failed.delete(file);
            })
            .catch((err) => {
                console.error(`[mi_fire] could not load ${file}: ${err.message}`);
                // Stays in `failed`, so it is not retried.
            });

        return null;
    }

    // -----------------------------------------------------------------------

    /**
     * Tear down one device's audio graph.
     * @param {string|number} id
     */
    function stop(id) {
        const entry = playing.get(id);
        if (!entry) return;

        if (entry.burstTimer) clearTimeout(entry.burstTimer);

        try {
            entry.source.stop();
        } catch (_) {
            /* already stopped */
        }

        try {
            entry.source.disconnect();
            entry.gain.disconnect();
            entry.panner.disconnect();
        } catch (_) {
            /* already disconnected */
        }

        playing.delete(id);
    }

    /**
     * Build source -> gain -> pan -> output for one device.
     * @param {string|number} id
     * @param {AudioBuffer} buffer
     * @param {boolean} loop
     * @param {number} rate
     */
    function start(id, buffer, loop, rate) {
        const context = audioContext();
        if (!context) return null;

        const source = context.createBufferSource();
        const gain = context.createGain();
        const panner = context.createStereoPanner();

        source.buffer = buffer;
        source.loop = loop;
        source.playbackRate.value = rate;

        source.connect(gain);
        gain.connect(panner);
        panner.connect(context.destination);

        gain.gain.value = 0;

        const entry = { source, gain, panner, loop, burstTimer: null };
        playing.set(id, entry);

        source.start(0);
        return entry;
    }

    /**
     * Play or update one device.
     *
     * `burst` plays a short slice on a repeating timer instead of looping, which is how a
     * single continuous alarm file becomes a pre-alarm chirp. It means one sound file
     * covers both phases; supplying a separate pre-alarm file sounds better and is
     * strictly optional.
     *
     * @param {object} data
     */
    function play(data) {
        const { id, file, volume, pan, rate, loop, burst, burstMs, gapMs } = data;

        const buffer = bufferFor(file);
        if (!buffer) return;

        let entry = playing.get(id);

        // Restart if the file or the play mode changed; otherwise just move it.
        if (entry && (entry.file !== file || entry.burstMode !== !!burst)) {
            stop(id);
            entry = null;
        }

        if (!entry) {
            entry = start(id, buffer, !!loop && !burst, rate || 1);
            if (!entry) return;
            entry.file = file;
            entry.burstMode = !!burst;

            if (burst) scheduleBurst(id, buffer, burstMs || 250, gapMs || 900);
        }

        const context = audioContext();
        const now = context ? context.currentTime : 0;

        // Ramp rather than jump. A volume that snaps as you turn your head sounds broken,
        // and 60ms is short enough to still feel responsive.
        const target = Math.max(0, Math.min(1, volume ?? 0));
        entry.gain.gain.setTargetAtTime(target, now, 0.06);
        entry.panner.pan.setTargetAtTime(Math.max(-1, Math.min(1, pan ?? 0)), now, 0.06);

        if (!entry.burstMode) {
            entry.source.playbackRate.value = rate || 1;
        } else {
            entry.burstMs = burstMs || 250;
            entry.gapMs = gapMs || 900;
        }
    }

    /**
     * Repeatedly play a short slice of the buffer, so one continuous alarm file can serve
     * as an escalating chirp.
     */
    function scheduleBurst(id, buffer, burstMs, gapMs) {
        const entry = playing.get(id);
        if (!entry) return;

        const context = audioContext();
        if (!context) return;

        // Each burst is its own short-lived source through the existing gain and pan, so
        // position changes apply to every chirp without rebuilding the graph.
        const source = context.createBufferSource();
        source.buffer = buffer;
        source.connect(entry.gain);
        source.start(0);
        source.stop(context.currentTime + burstMs / 1000);

        entry.burstTimer = setTimeout(() => {
            if (playing.has(id)) {
                scheduleBurst(id, buffer, entry.burstMs || burstMs, entry.gapMs || gapMs);
            }
        }, (entry.burstMs || burstMs) + (entry.gapMs || gapMs));
    }

    // -----------------------------------------------------------------------

    window.addEventListener('message', (event) => {
        const data = event.data;
        if (!data || typeof data !== 'object') return;

        switch (data.action) {
            case 'pass':
                play(data);
                break;

            case 'passStop':
                stop(data.id);
                break;

            case 'stopAll':
                for (const id of Array.from(playing.keys())) stop(id);
                break;

            default:
                break;
        }
    });
})();
