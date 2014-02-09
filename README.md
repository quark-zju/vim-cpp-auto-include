Automatically insert or delete `#include`s for C++ code in vim.

![vim-cpp-auto-include demo](https://raw.github.com/quark-zju/vim-cpp-auto-include/master/demo/vim-cpp-auto-include-demo.gif)

Note
====
This plugin is intended to be simple 
and intended to be used on simple C++ files only. 

Installation
============
Copy [`plugin/cpp_auto_include.vim`](/quark-zju/vim-cpp-auto-include/raw/master/plugin/cpp_auto_include.vim) to `~/.vim/plugin/`.

Alternatively, with [Vundle](/gmarik/vundle), 
add `Bundle 'quark-zju/vim-cpp-auto-include'` in `~/.vimrc` 
and run `BundleInstall` in vim.

Usage
=====
`:w`

Configuration
=============
Only C++ files in `/tmp` are processed by default.

Add following line in your `.vimrc` to make your C++ code 
in `/some/path/` processed when saving:

```viml
autocmd BufWritePre /some/path/**.cpp :ruby CppAutoInclude::process
```
If you want more control, feel free to edit the source :)


