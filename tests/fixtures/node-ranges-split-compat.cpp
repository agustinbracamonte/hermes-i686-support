#include <cstdio>
#include <ranges>
#include <string>
#include <string_view>

using std::operator""sv;

int main() {
  std::string options = "stderr,http";
  auto entries = std::views::split(options, ","sv);
  bool console = false;
  bool http = false;
  for (const auto& entry : entries) {
    std::string destination(entry.begin(), entry.end());
    if (destination == "stderr") {
      console = true;
    } else if (destination == "http") {
      http = true;
    }
  }
  if (!console || !http) return 1;
  std::puts("ranges_split_view=PASS");
  return 0;
}
