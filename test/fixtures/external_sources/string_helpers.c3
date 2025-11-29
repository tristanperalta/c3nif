// External C3 source file for testing glob pattern expansion
module string_helpers;

// Calculate the length of a null-terminated string
fn usz string_length(char* str) {
    usz len = 0;
    while (str[len] != 0) {
        len++;
    }
    return len;
}
