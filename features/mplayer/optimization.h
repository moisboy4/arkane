#pragma once
#include <vector>
#include <memory>
#include <cstring>
#include <cwchar>
#include <Windows.h>
#include <winrt/Windows.Foundation.h>

class StringPool {
public:
    char* allocate(const winrt::hstring& source) {
        int needed = WideCharToMultiByte(CP_UTF8, 0, source.c_str(), -1, nullptr, 0, nullptr, nullptr);
        if (needed <= 0) {
            auto empty = std::make_unique<char[]>(1);
            empty[0] = '\0';
            pool_.push_back(std::move(empty));
            return pool_.back().get();
        }

        auto buf = std::make_unique<char[]>(needed);
        WideCharToMultiByte(CP_UTF8, 0, source.c_str(), -1, buf.get(), needed, nullptr, nullptr);

        char* ptr = buf.get();
        pool_.push_back(std::move(buf));
        return ptr;
    }

    void clear() noexcept {
        pool_.clear();
    }

private:
    std::vector<std::unique_ptr<char[]>> pool_;
};
