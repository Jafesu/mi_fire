/*
 * The fireground HUD.
 *
 * Three numbers a firefighter actually needs and cannot get any other way: how much air is
 * left, what condition the coat is in, and how much heat is going into it. Everything else
 * about the fireground is visible in the world, so it does not belong here.
 *
 * Written as plain DOM against the existing NUI page rather than pulled into a framework.
 * When the pump panel's React app becomes the ui_page in Phase 4 this becomes a component
 * in it, which is a small and known migration -- and until then it costs no build step.
 *
 * Nothing here takes focus or swallows a click; the page is pointer-events: none.
 */

(() => {
    'use strict';

    const root = document.createElement('div');
    root.id = 'mi-hud';
    root.innerHTML = `
        <div class="row" id="air" hidden>
            <span class="label">AIR</span>
            <span class="bar"><i></i></span>
            <span class="value"></span>
        </div>
        <div class="row" id="gear" hidden>
            <span class="label">GEAR</span>
            <span class="bar"><i></i></span>
            <span class="value"></span>
        </div>
        <div class="row" id="heat" hidden>
            <span class="label">HEAT</span>
            <span class="bar"><i></i></span>
            <span class="value"></span>
        </div>
    `;
    document.body.appendChild(root);

    const rows = {
        air: root.querySelector('#air'),
        gear: root.querySelector('#gear'),
        heat: root.querySelector('#heat'),
    };

    /** mm:ss, because a bottle is read in minutes remaining and never in percent. */
    const clock = (seconds) => {
        const s = Math.max(0, Math.round(seconds));
        return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
    };

    /**
     * @param {HTMLElement} row
     * @param {boolean} show
     * @param {number} fraction 0-1, drives the bar
     * @param {string} text
     * @param {string} state '' | 'warn' | 'critical'
     */
    const set = (row, show, fraction, text, state) => {
        row.hidden = !show;
        if (!show) return;
        row.querySelector('i').style.width = `${Math.max(0, Math.min(1, fraction)) * 100}%`;
        row.querySelector('.value').textContent = text;
        row.dataset.state = state || '';
    };

    window.addEventListener('message', (event) => {
        const data = event.data;
        if (!data || data.action !== 'hud') return;

        const air = data.air;
        if (air && air.worn) {
            const fraction = air.capacity > 0 ? air.seconds / air.capacity : 0;
            // Colour tracks the real alarm points rather than arbitrary thirds, so the bar
            // turns red at the same moment the low-air alarm sounds.
            const state = fraction <= air.criticalAt ? 'critical'
                : fraction <= air.lowAt ? 'warn' : '';
            // A closed valve is the state people misread most, so it is said in words.
            const text = air.active ? clock(air.seconds) : `${clock(air.seconds)} · CLOSED`;
            set(rows.air, true, fraction, text, air.active ? state : 'warn');
        } else {
            set(rows.air, false);
        }

        const gear = data.gear;
        // Only shown once it is worth knowing. A full set is not news.
        if (gear && gear.worn && gear.fraction < 0.999) {
            const state = gear.condemned ? 'critical' : gear.fraction < 0.4 ? 'warn' : '';
            set(rows.gear, true, gear.fraction, gear.condition, state);
        } else {
            set(rows.gear, false);
        }

        const heat = data.heat;
        if (heat && heat.fraction > 0.15) {
            const state = heat.fraction >= 0.75 ? 'critical'
                : heat.fraction >= 0.5 ? 'warn' : '';
            set(rows.heat, true, heat.fraction, `${Math.round(heat.fraction * 100)}%`, state);
        } else {
            set(rows.heat, false);
        }
    });
})();
