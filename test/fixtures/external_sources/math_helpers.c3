// External C3 source file for testing c3_sources option
module math_helpers;

// Simple multiply function that can be called from the main NIF module
fn int multiply(int a, int b) {
    return a * b;
}

// Square function
fn int square(int n) {
    return multiply(n, n);
}
