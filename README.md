Automatically insert or delete `#include`s for C++ code in vim.

![vim-cpp-auto-include demo](/quark_zju/vim-cpp-auto-include/raw/master/demo/vim-cpp-auto-include-demo.gif)

Installation
============
Copy `plugin/cpp_auto_include.vim` to `~/.vim/plugin/`.

Alternatively, with [Vundle](/gmarik/vundle), 
add `Bundle 'quark_zju/vim-cpp-auto-include'` in `~/.vimrc` 
and run `BundleInstall` in vim.

Usage
=====
`:w`

Configuration
=============
Add following line in your `.vimrc` to make your C++ code 
in `/some/path/` processed:

```viml
autocmd BufWritePre /some/path/**.cpp :ruby CppAutoInclude::process
```

C++ files in `/tmp` are processed by default.

This plugin is intended to be simple 
and intended to be used on simple C++ files only. 
If you want more control, feel free to edit the source :p


