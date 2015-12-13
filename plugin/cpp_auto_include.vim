" Copyright (C) 2012 WU Jun <quark@zju.edu.cn>
" 
" Permission is hereby granted, free of charge, to any person obtaining a copy
" of this software and associated documentation files (the "Software"), to deal
" in the Software without restriction, including without limitation the rights
" to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
" copies of the Software, and to permit persons to whom the Software is
" furnished to do so, subject to the following conditions:
" 
" The above copyright notice and this permission notice shall be included in
" all copies or substantial portions of the Software.
" 
" THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
" IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
" FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
" AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
" LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
" OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
" THE SOFTWARE.

if exists("g:loaded_cpp_auto_include")
    finish
endif

if !has("ruby")
    echohl ErrorMsg
    echon "Sorry, cpp_auto_include requires ruby support."
    finish
endif

let g:loaded_cpp_auto_include = "true"

autocmd BufWritePre /tmp/**.cc :ruby CppAutoInclude::process
autocmd BufWritePre /tmp/**.cpp :ruby CppAutoInclude::process

ruby << EOF
module VIM
  # make VIM's builtin VIM ruby module a little easier to use
  class << self
    # ['line1', 'line2' ... ]
    # [['line1', 1], ['line2', 2] ... ] if with_numbers
    def lines(with_numbers = false)
      lines = $curbuf.length.times.map { |i| $curbuf[i + 1] }
      with_numbers ? lines.zip(1..$curbuf.length) : lines
    end

    # if the line after #i != content,
    # append content after line #i
    def append(i, content)
      return false if ($curbuf.length >= i+1 && $curbuf[i+1] == content) 
      cursor = $curwin.cursor
      $curbuf.append(i, content)
      $curwin.cursor = [cursor.first+1,cursor.last] if cursor.first >= i
    end

    # remove line #i while (line #i = content)
    # or remove line #i once if content is nil
    # or find and remove line = content if i is nil
    def remove(i, content = nil)
      i ||= $curbuf.length.times { |i| break i + 1 if $curbuf[i + 1] == content }
      return if i.nil?

      content ||= $curbuf[i]

      while $curbuf[i] == content && i <= $curbuf.length
        cursor = $curwin.cursor
        $curbuf.delete(i)
        $curwin.cursor = [[1,cursor.first-1].max,cursor.last] if cursor.first >= i
        break if i >= $curbuf.length
      end
    end
  end
end


module CppAutoInclude
  # shortcut to generate regex
  C = proc do |*names| names.map { |name| /\b?#{name}\b/ } end
  F = proc do |*names| names.map { |name| /\b?#{name}\s*\(/ } end
  T = proc do |*names| names.map { |name| /\b?#{name}\s*<\b/ } end
  R = proc do |*regexs| Regexp.union(regexs.flatten) end

  # header, std namespace, keyword complete (false: no auto remove #include), unioned regex
  HEADER_STD_COMPLETE_REGEX = [
    ['algorithm'     , true , true , R[F['move(?:_backward)?', 'find(?:_(?:(?:if(?:_not)?)|end|(?:first_of))?)?', '(?:stable_|partial_)?sort(?:_copy)?', 'unique(?:_copy)?', 'reverse(?:_copy)?', 'nth_element', '(?:lower|upper)_bound', 'binary_search', '(?:prev|next)_permutation', 'min', 'max', 'count(?:_if)?', 'random_shuffle', 'swap', 'all_of', 'any_of', 'none_of', 'copy(?:_if)?']] ],
    ['array'         , true , true , R[T['array']] ],
    ['atomic'        , true , true , R[T['atomic_']] ],
    ['bitset'        , true , true , R[T['bitset']] ],
    ['bitset'        , true , true , R[T['bitset']] ],
    ['cassert'       , false, true , R[F['assert']] ],
    ['chrono'        , true , true , R[C['chrono::duration', 'chrono::time_point']],],
    ['cmath'         , false, true , R[F['pow[fl]?','a?(?:sin|cos|tan)[hl]*', 'atan2[fl]?', 'exp[m12fl]*', 'fabs[fl]?', 'log[210fl]+', 'nan[fl]?', '(?:ceil|floor)[fl]?', 'l?l?round[fl]?', 'sqrt[fl]?'], C['M_[A-Z24_]*', 'NAN', 'INFINITY', 'HUGE_[A-Z]*']] ],
    ['complex'       , true , true , R[T['complex']] ],
    ['cstdio'        , false, true , R[F['s?scanf', 'puts', 's?printf', 'f?gets', '(?:get|put)char', 'getc'], C['FILE','std(?:in|out|err)','EOF']] ],
    ['cstdlib'       , false, true , R[F['system','abs','ato[if]', 'itoa', 'strto[dflu]+','free','exit','l?abs','s?rand(?:_r|om)?','qsort'], C['EXIT_[A-Z]*', 'NULL']] ],
    ['cstring'       , false, true , R[F['mem(?:cpy|set|n?cmp)', 'str(?:len|n?cmp|n?cpy|error|cat|str|chr)']] ],
    ['ctime'         , false, true , R[F['time', 'clock'], C['CLOCKS_PER_SEC']]],
    ['cuchar'        , true , true , R[F['mbrtoc(?:16|32)', 'c(?:16|32)rtomb']] ],
    ['deque'         , true , true , R[T['deque']] ],
    ['forward_list'  , true , true , R[T['forward_list']] ],
    ['fstream'       , true , true , R[T['fstream']] ],
    ['functional'    , true , true , R[T['unary_function', 'binary_function', 'ref', 'cref', 'plus', 'minus', 'multiplies', 'divides', 'modulus', 'negate', 'equal_to', 'not_equal_to', 'greater', 'less', 'greater_equal', 'less_equal', 'logical_and', 'logical_or', 'logical_not', 'bit_and', 'bit_or', 'bit_xor', 'mem_fn', 'mem_fun_ref', 'function', 'pointer_to_unary_function', 'pointer_to_binary_function', 'binder1st', 'binder2nd', 'is_bind_expression', 'is_placeholder', 'bind', 'unary_negate', 'binary_negate' ]] ],
    ['iomanip'       , true , true , R[F['setprecision', 'setiosflags', 'setbase', 'setw', '(?:set|put)_(?:money|time)'], C['fixed', 'hex']]],
    ['iostream'      , true , true , R[C['c(?:err|out|in)']] ],
    ['limits'        , true , true , R[T['numeric_limits']] ],
    ['list'          , true , true , R[T['list']] ],
    ['map'           , true , true , R[T['(?:multi)?map']] ],
    ['mutex'         , true , true , R[C['lock_guard', 'unique_lock'], F['try_lock', 'lock', 'call_once'], T['(?:recursive_)?(?:timed_)?mutex', 'defer_lock', 'try_to_lock', 'adopt_lock']] ],
    ['new'           , true , true , R[F['set_new_handler'], C['nothrow']] ],
    ['numeric'       , true , true , R[F['partial_sum', 'accumulate', 'adjacent_difference', 'inner_product']] ],
    ['queue'         , true , true , R[T['queue','priority_queue']] ],
    ['set'           , true , true , R[T['(?:multi)?set']] ],
    ['sstream'       , true , true , R[C['[io]?stringstream']] ],
    ['string'        , true , true , R[C['string']] ],
    ['strings.h'     , false, true , R[F['b(?:cmp|copy|zero)', 'strn?casecmp']] ],
    ['thread'        , true , true , R[C['thread'], F['this_thread::yield', 'this_thread::get_id', 'this_thread::sleep_until', 'this_thread::sleep_for']],],
    ['tuple'         , true , true , R[T['tuple'], F['make_tuple', 'tie', 'tuple_cat', 'forward_as_tuple']] ],
    ['type_traits'   , true , true , R[T['is_void', 'is_null_pointer', 'is_integral', 'is_floating_point', 'is_array', 'is_pointer', 'is_lvalue_reference', 'is_rvalue_reference', 'is_member_object_pointer', 'is_member_function_pointer', 'is_enum', 'is_union', 'is_class', 'is_function', 'is_reference', 'is_arithmetic', 'is_fundamental', 'is_object', 'is_scalar', 'is_compound', 'is_member_pointer', 'is_const', 'is_volatile', 'is_trivial', 'is_trivially_copyable', 'is_standard_layout', 'is_pod', 'is_literal_type', 'is_empty', 'is_polymorphic', 'is_abstract', 'is_signed', 'is_unsigned', 'is_constructible', 'is_default_constructible', 'is_copy_constructible', 'is_move_constructible', 'is_assignable', 'is_copy_assignable', 'is_move_assignable', 'is_destructible', 'is_trivially_constructible', 'is_trivially_default_constructible', 'is_trivially_copy_constructible', 'is_trivially_move_constructible', 'is_trivially_assignable', 'is_trivially_copy_assignable', 'is_trivially_move_assignable', 'is_trivially_destructible', 'is_nothrow_constructible', 'is_nothrow_default_constructible', 'is_nothrow_copy_constructible', 'is_nothrow_move_constructible', 'is_nothrow_assignable', 'is_nothrow_copy_assignable', 'is_nothrow_move_assignable', 'is_nothrow_destructible', 'has_virtual_destructor', 'alignment_of', 'rank', 'extent', 'is_same', 'is_base_of', 'is_convertible', 'remove_const', 'remove_volatile', 'remove_cv', 'add_const', 'add_volatile', 'add_cv', 'remove_reference', 'add_lvalue_reference', 'add_rvalue_reference', 'make_signed', 'make_unsigned', 'remove_extent', 'remove_all_extents', 'remove_pointer', 'add_pointer', 'aligned_storage', 'decay', 'enable_if', 'conditional', 'common_type', 'underlying_type', 'result_of']] ],
    ['typeindex'     , true , true , R[T['type_index']] ],
    ['typeinfo'      , false, true , R[C['typeid']] ],
    ['unordered_map' , true , true , R[T['unordered_(?:multi)?map']] ],
    ['unordered_set' , true , true , R[T['unordered_(?:multi)?set']] ],
    ['utility'       , true , true , R[T['pair'], F['make_pair', 'forward', 'exchange']] ],
    ['vector'        , true , true , R[T['vector']] ],
  ]

  USING_STD       = 'using namespace std;'

  # do nothing if lines.count > LINES_THRESHOLD
  LINES_THRESHOLD = 1000

  class << self
    def includes_and_content
      # split includes and other content
      includes, content = [['', 0]], ''
      VIM::lines.each_with_index do |l, i|
        if l =~ /^\s*#\s*include/
          includes << [l, i+1]
        elsif l =~ /^\s*namespace/ and includes.length == 1
          includes << ['', i]
        else
          content << l.gsub(/\/\/[^"]*(?:"[^"']*"[^"]*)*$/,'') << "\n"
        end
      end
      [includes, content]
    end

    def process
      return if $curbuf.length > LINES_THRESHOLD

      begin
        use_std, includes, content = false, *includes_and_content

        # process each header
        HEADER_STD_COMPLETE_REGEX.each do |header, std, complete, regex|
          has_header  = includes.detect { |l| l.first.include? "<#{header}>" }
					if (std)
						rex = Regexp.new "(std::)("+regex.source+")"
					else 
						rex = regex
					end
          has_keyword = (has_header && !complete) || (content =~ rex)
          use_std ||= std && has_keyword && $1 != "std::"

          if has_keyword && !has_header
            VIM::append(includes.last.last, "#include <#{header}>")
            includes = includes_and_content.first
          elsif !has_keyword && has_header && complete
            VIM::remove(has_header.last)
            includes = includes_and_content.first
          end
        end

        # append empty line to last #include 
        # or remove top empty lines if no #include
        if includes.last.last == 0
          VIM::remove(1, '')
        else
          VIM::append(includes.last.last, '')
        end

        # add / remove 'using namespace std'
        has_std = content[USING_STD]

        if use_std && !has_std && !includes.empty?
          VIM::append(includes.last.last+1, USING_STD) 
          VIM::append(includes.last.last+2, '')
        elsif !use_std && has_std
          VIM::remove(nil, USING_STD)
          VIM::remove(1, '') if includes.last.last == 0
        end
      rescue => ex
        # VIM hide backtrace information by default, re-raise with backtrace
        raise RuntimeError.new("#{ex.message}: #{ex.backtrace}")
      end
    end
  end
end
EOF

" vim: nowrap
