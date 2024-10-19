pub const Envelope = struct {
    state: State = State.attack,
    attack: Stage,
    decay: Stage,
    release: Stage,
    currentMult: f32 = 0,

    pub const State = enum { attack, decay, sustain, release, end };

    const Stage = struct {
        samplesLeft: f32,
        samplesTotal: f32,
        startMultiplier: f32 = 0, // Set this to currentMult when stage started
        endMultiplier: f32,
        calculateMult: *const fn (self: *Stage) f32 = &linear,

        fn init(sampleRate: f64, durationMs: f32, target: f32) Stage {
            const releaseTotal: f32 = @floor(@as(f32, @floatCast(sampleRate)) * durationMs / 1000.0);
            return Stage{
                .samplesLeft = releaseTotal,
                .samplesTotal = releaseTotal,
                .endMultiplier = target,
            };
        }

        fn getMult(self: *Stage) f32 {
            return self.calculateMult(self);
        }

        fn linear(self: *Stage) f32 {
            const difference = self.endMultiplier - self.startMultiplier;
            const percentLeft = if (self.samplesTotal == 0) 0 else self.samplesLeft / self.samplesTotal;

            return self.endMultiplier - (difference * percentLeft);
        }

        fn constant(self: *Stage) f32 {
            return self.endMultiplier;
        }
    };

    pub fn apply(self: *Envelope, value: f32) f32 {
        const mult = switch (self.state) {
            State.attack => self.attack.getMult(),
            State.decay => self.decay.getMult(),
            State.sustain => self.currentMult,
            State.release => self.release.getMult(),
            State.end => 0,
        };

        self.currentMult = mult;

        return value * mult;
    }

    pub fn advance(self: *Envelope) void {
        switch (self.state) {
            State.attack => {
                self.attack.samplesLeft -= 1;
                if (self.attack.samplesLeft <= 0) {
                    self.decay.startMultiplier = self.currentMult;
                    self.state = State.decay;
                }
            },
            State.decay => {
                self.decay.samplesLeft -= 1;
                if (self.decay.samplesLeft <= 0) self.state = State.sustain;
            },
            State.sustain => {
                self.release.startMultiplier = self.currentMult;
                self.state = State.release;
            },
            State.release => {
                self.release.samplesLeft -= 1;
                if (self.release.samplesLeft <= 0) self.state = State.end;
            },
            State.end => {},
        }
    }

    pub fn default(sampleRate: f64) Envelope {
        return Envelope{
            .attack = Stage.init(sampleRate, 2, 1),
            .decay = Stage.init(sampleRate, 2, 1),
            .release = Stage.init(sampleRate, 2, 0),
        };
    }
};
