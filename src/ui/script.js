const paramGroups = document.querySelectorAll('.param-group');

paramGroups.forEach(group => {
    const knobs = group.querySelectorAll('.param .knob');
    const buttons = group.querySelectorAll('.param .toggle');
    const waves = group.querySelectorAll('.param .wave');

    waves.forEach(wave => {
        wave.parentElement.addEventListener('input', function(event) {
            wave.querySelector('svg use')
                .setAttribute('href', `waves/${event.target.value}.svg#svg`);
        });
    });

    buttons.forEach(button => {
        button.onclick = function(event) {
            const checkbox = button.parentElement.querySelector("input[type=checkbox]");

            if (checkbox.checked) {
                button.querySelector(".light").classList.remove("light-pulse");
                checkbox.checked = false;
                checkbox.value = "off";
            } else {
                button.querySelector(".light").classList.add("light-pulse");
                checkbox.checked = true;
                checkbox.value = "on";
            }
        }
    });


    knobs.forEach(knob => {
        knob.zeroed = knob.classList.contains('zeroed');
        knob.currentY = 0;
        knob.currentX = 0;
        knob.current = 0;
        knob.maxRot = 140;
        knob.speed = 3;
        knob.girth = 3;

        knob.onpointerdown = function(event) {
            event.preventDefault();
            document.addEventListener('pointermove', move);
            document.addEventListener('pointerup', stop);

            knob.currentY = event.clientY;
            knob.currentX = event.clientX;
        };

        knob.ondblclick = function(event) {
            const input = knob.parentElement.querySelector("input");
            const defaultValue = input.defaultValue;

            input.value = defaultValue;
            input.dispatchEvent(new Event("input", { bubbles: true }));
        };

        knob.parentElement.addEventListener('input', handleInput);
        knob.parentElement.querySelector("input").dispatchEvent(new Event("input", { bubbles: true }));

        function move(event) {
            const deltaY = knob.currentY - event.clientY;
            const deltaX = knob.currentX - event.clientX;

            knob.currentY = event.clientY;
            knob.currentX = event.clientX;
            knob.current += knob.speed * (deltaY - deltaX) / 2;

            if (knob.current > knob.maxRot) knob.current = knob.maxRot;
            if (knob.current < -knob.maxRot) knob.current = -knob.maxRot;

            updateInput();
        }

        function drawKnob() {
            const indicator = knob.querySelector('.indicator');
            const gagueFill = knob.querySelector(".gague-fill");
            indicator.style.transform = "rotate(" + knob.current + "deg)";

            if (knob.zeroed) {
                gagueFill.style.background = `conic-gradient(from 220deg, #4fd6be ${knob.maxRot + knob.current + knob.girth}deg, rgba(255,255,255,0.0) 0deg)`;
            } else {
                gagueFill.style.background = `conic-gradient(#4fd6be ${knob.current + knob.girth}deg, rgba(255,255,255,0.0) 0 ${360 + knob.current - knob.girth}deg, #4fd6be ${knob.girth}deg)`;
            }
        }

        function updateInput() {
            const input = knob.parentElement.querySelector('input');
            const knobRange = 2 * knob.maxRot;
            const inputRange = input.max - input.min;
            const ratio = Math.abs((knob.current - knob.maxRot) / knobRange);
            const value = parseInt(input.max) - (ratio * inputRange);
            const step = parseFloat(input.step);

            if (step > 0 && step < 1) {
                input.value = (Math.round(value / step) * step).toFixed(2);
            } else {
                input.value = Math.round(value / step) * step;
            }

            knob.parentElement.querySelector("input").dispatchEvent(new Event("input", { bubbles: true }));
        }

        function handleInput(event) {
            const raw = event.target.value.trim();
            const value = parseInt(raw);
            const min = parseInt(event.target.min);
            const max = parseInt(event.target.max);

            if (raw === '') return;
            if (raw === '-' && min < 0) return;
            if (isNaN(value)) event.target.value = min;
            if (value > max) event.target.value = max;
            if (value < min) event.target.value = min;

            const knobRange = 2 * knob.maxRot;
            const inputRange = event.target.max - event.target.min;
            const ratio = Math.abs((min - event.target.value) / inputRange);
            knob.current = (ratio * knobRange) - knob.maxRot;

            drawKnob();

            updateSynth(value, min, max);
        }

        function stop() {
            document.removeEventListener('pointermove', move);
            document.removeEventListener('pointerup', stop);
        }
    });
});
