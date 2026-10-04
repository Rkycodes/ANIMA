# Numeric design â€” draft
Begin with a floating-point reference, then implement an explicitly bit-exact fixed-point model before DSP RTL.

Candidate formats for evaluation: 32-bit internal samples with 27 fractional bits, 32-bit coefficients with 29 fractional bits, wider filter state (candidate 40 bits), and wide accumulators (candidate 80 bits). These are not frozen interfaces.

Document total width, signedness, fractional bits, intermediate widths, rounding, saturation, and coefficient ordering for every block. Specify the biquad equation and feedback signs explicitly; names such as a1 are insufficient to define the sign convention.

Evaluate quantized pole stability, boost headroom across the cascade, silence limit cycles, state overflow, full-scale overload, and transitions between presets. Left and right use independent state with identical coefficients.

Choose coefficient smoothing or another measured transition strategy if instantaneous stable coefficient changes click or create unacceptable transients. Do not assume frame-boundary atomicity alone prevents clicks.
