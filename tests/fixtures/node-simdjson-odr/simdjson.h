#pragma once
#include <cstddef>
#include <string>

#define SIMDJSON_CONSTEXPR_STRING

namespace simdjson {
namespace implementation_0 {
namespace key_selector_detail {
// --- describe() string helpers (constexpr; no std::to_string, which is not) ---

// Append the decimal form of v to s.
SIMDJSON_CONSTEXPR_STRING void append_uint(std::string& s, std::size_t v) {
    if (v == 0) { s.push_back('0'); return; }
    char buf[20];
    std::size_t n = 0;
    while (v > 0) { buf[n++] = static_cast<char>('0' + (v % 10)); v /= 10; }
    while (n > 0) { s.push_back(buf[--n]); }
}

// Append a byte as its decimal value, plus the printable character in quotes
// when it is in the printable ASCII range (e.g. "110 ('n')").
SIMDJSON_CONSTEXPR_STRING void append_byte(std::string& s, unsigned b) {
    append_uint(s, b);
    if (b >= 0x20 && b < 0x7f) {
        s += " ('";
        s.push_back(static_cast<char>(b));
        s += "')";
    }
}
}
}
namespace implementation_1 {
namespace key_selector_detail {
// --- describe() string helpers (constexpr; no std::to_string, which is not) ---

// Append the decimal form of v to s.
SIMDJSON_CONSTEXPR_STRING void append_uint(std::string& s, std::size_t v) {
    if (v == 0) { s.push_back('0'); return; }
    char buf[20];
    std::size_t n = 0;
    while (v > 0) { buf[n++] = static_cast<char>('0' + (v % 10)); v /= 10; }
    while (n > 0) { s.push_back(buf[--n]); }
}

// Append a byte as its decimal value, plus the printable character in quotes
// when it is in the printable ASCII range (e.g. "110 ('n')").
SIMDJSON_CONSTEXPR_STRING void append_byte(std::string& s, unsigned b) {
    append_uint(s, b);
    if (b >= 0x20 && b < 0x7f) {
        s += " ('";
        s.push_back(static_cast<char>(b));
        s += "')";
    }
}
}
}
namespace implementation_2 {
namespace key_selector_detail {
// --- describe() string helpers (constexpr; no std::to_string, which is not) ---

// Append the decimal form of v to s.
SIMDJSON_CONSTEXPR_STRING void append_uint(std::string& s, std::size_t v) {
    if (v == 0) { s.push_back('0'); return; }
    char buf[20];
    std::size_t n = 0;
    while (v > 0) { buf[n++] = static_cast<char>('0' + (v % 10)); v /= 10; }
    while (n > 0) { s.push_back(buf[--n]); }
}

// Append a byte as its decimal value, plus the printable character in quotes
// when it is in the printable ASCII range (e.g. "110 ('n')").
SIMDJSON_CONSTEXPR_STRING void append_byte(std::string& s, unsigned b) {
    append_uint(s, b);
    if (b >= 0x20 && b < 0x7f) {
        s += " ('";
        s.push_back(static_cast<char>(b));
        s += "')";
    }
}
}
}
namespace implementation_3 {
namespace key_selector_detail {
// --- describe() string helpers (constexpr; no std::to_string, which is not) ---

// Append the decimal form of v to s.
SIMDJSON_CONSTEXPR_STRING void append_uint(std::string& s, std::size_t v) {
    if (v == 0) { s.push_back('0'); return; }
    char buf[20];
    std::size_t n = 0;
    while (v > 0) { buf[n++] = static_cast<char>('0' + (v % 10)); v /= 10; }
    while (n > 0) { s.push_back(buf[--n]); }
}

// Append a byte as its decimal value, plus the printable character in quotes
// when it is in the printable ASCII range (e.g. "110 ('n')").
SIMDJSON_CONSTEXPR_STRING void append_byte(std::string& s, unsigned b) {
    append_uint(s, b);
    if (b >= 0x20 && b < 0x7f) {
        s += " ('";
        s.push_back(static_cast<char>(b));
        s += "')";
    }
}
}
}
namespace implementation_4 {
namespace key_selector_detail {
// --- describe() string helpers (constexpr; no std::to_string, which is not) ---

// Append the decimal form of v to s.
SIMDJSON_CONSTEXPR_STRING void append_uint(std::string& s, std::size_t v) {
    if (v == 0) { s.push_back('0'); return; }
    char buf[20];
    std::size_t n = 0;
    while (v > 0) { buf[n++] = static_cast<char>('0' + (v % 10)); v /= 10; }
    while (n > 0) { s.push_back(buf[--n]); }
}

// Append a byte as its decimal value, plus the printable character in quotes
// when it is in the printable ASCII range (e.g. "110 ('n')").
SIMDJSON_CONSTEXPR_STRING void append_byte(std::string& s, unsigned b) {
    append_uint(s, b);
    if (b >= 0x20 && b < 0x7f) {
        s += " ('";
        s.push_back(static_cast<char>(b));
        s += "')";
    }
}
}
}
namespace implementation_5 {
namespace key_selector_detail {
// --- describe() string helpers (constexpr; no std::to_string, which is not) ---

// Append the decimal form of v to s.
SIMDJSON_CONSTEXPR_STRING void append_uint(std::string& s, std::size_t v) {
    if (v == 0) { s.push_back('0'); return; }
    char buf[20];
    std::size_t n = 0;
    while (v > 0) { buf[n++] = static_cast<char>('0' + (v % 10)); v /= 10; }
    while (n > 0) { s.push_back(buf[--n]); }
}

// Append a byte as its decimal value, plus the printable character in quotes
// when it is in the printable ASCII range (e.g. "110 ('n')").
SIMDJSON_CONSTEXPR_STRING void append_byte(std::string& s, unsigned b) {
    append_uint(s, b);
    if (b >= 0x20 && b < 0x7f) {
        s += " ('";
        s.push_back(static_cast<char>(b));
        s += "')";
    }
}
}
}
namespace implementation_6 {
namespace key_selector_detail {
// --- describe() string helpers (constexpr; no std::to_string, which is not) ---

// Append the decimal form of v to s.
SIMDJSON_CONSTEXPR_STRING void append_uint(std::string& s, std::size_t v) {
    if (v == 0) { s.push_back('0'); return; }
    char buf[20];
    std::size_t n = 0;
    while (v > 0) { buf[n++] = static_cast<char>('0' + (v % 10)); v /= 10; }
    while (n > 0) { s.push_back(buf[--n]); }
}

// Append a byte as its decimal value, plus the printable character in quotes
// when it is in the printable ASCII range (e.g. "110 ('n')").
SIMDJSON_CONSTEXPR_STRING void append_byte(std::string& s, unsigned b) {
    append_uint(s, b);
    if (b >= 0x20 && b < 0x7f) {
        s += " ('";
        s.push_back(static_cast<char>(b));
        s += "')";
    }
}
}
}
namespace implementation_7 {
namespace key_selector_detail {
// --- describe() string helpers (constexpr; no std::to_string, which is not) ---

// Append the decimal form of v to s.
SIMDJSON_CONSTEXPR_STRING void append_uint(std::string& s, std::size_t v) {
    if (v == 0) { s.push_back('0'); return; }
    char buf[20];
    std::size_t n = 0;
    while (v > 0) { buf[n++] = static_cast<char>('0' + (v % 10)); v /= 10; }
    while (n > 0) { s.push_back(buf[--n]); }
}

// Append a byte as its decimal value, plus the printable character in quotes
// when it is in the printable ASCII range (e.g. "110 ('n')").
SIMDJSON_CONSTEXPR_STRING void append_byte(std::string& s, unsigned b) {
    append_uint(s, b);
    if (b >= 0x20 && b < 0x7f) {
        s += " ('";
        s.push_back(static_cast<char>(b));
        s += "')";
    }
}
}
}
namespace implementation_8 {
namespace key_selector_detail {
// --- describe() string helpers (constexpr; no std::to_string, which is not) ---

// Append the decimal form of v to s.
SIMDJSON_CONSTEXPR_STRING void append_uint(std::string& s, std::size_t v) {
    if (v == 0) { s.push_back('0'); return; }
    char buf[20];
    std::size_t n = 0;
    while (v > 0) { buf[n++] = static_cast<char>('0' + (v % 10)); v /= 10; }
    while (n > 0) { s.push_back(buf[--n]); }
}

// Append a byte as its decimal value, plus the printable character in quotes
// when it is in the printable ASCII range (e.g. "110 ('n')").
SIMDJSON_CONSTEXPR_STRING void append_byte(std::string& s, unsigned b) {
    append_uint(s, b);
    if (b >= 0x20 && b < 0x7f) {
        s += " ('";
        s.push_back(static_cast<char>(b));
        s += "')";
    }
}
}
}
}
