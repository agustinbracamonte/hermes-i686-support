#include "simdjson.h"

std::string odr_from_b() {
  std::string result;
  simdjson::implementation_1::key_selector_detail::append_byte(result, 'A');
  return result;
}
