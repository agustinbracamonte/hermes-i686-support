#include <cstdio>
#include <ranges>
#include <set>
#include <string>
#include <string_view>
#include <utility>

using std::operator""sv;

template <typename String>
std::set<std::string> split_categories(String& categories) {
  auto parts = std::views::split(categories, ","sv);
  std::set<std::string> categories_set;
  for (const auto& part : parts) {
    std::string category;
    for (char character : part) category.push_back(character);
    categories_set.emplace(std::move(category));
  }
  return categories_set;
}

int main() {
  std::string mutable_categories = "stderr,http,stderr";
  const std::string const_categories = "v8,node";
  const auto mutable_result = split_categories(mutable_categories);
  const auto const_result = split_categories(const_categories);
  if (mutable_result.size() != 2 || !mutable_result.contains("stderr") ||
      !mutable_result.contains("http")) {
    return 1;
  }
  if (const_result.size() != 2 || !const_result.contains("v8") ||
      !const_result.contains("node")) {
    return 1;
  }
  std::puts("ranges_split_view=PASS");
  return 0;
}
