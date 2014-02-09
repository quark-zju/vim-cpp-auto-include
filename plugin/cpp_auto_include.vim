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
  C = proc do |*names| names.map { |name| /\b#{name}\b/ } end
  F = proc do |*names| names.map { |name| /\b#{name}\s*\(/ } end
  T = proc do |*names| names.map { |name| /\b#{name}\s*<\b/ } end
  R = proc do |*regexs| Regexp.union(regexs.flatten) end

  # header, std namespace, keyword complete (false: no auto remove #include), unioned regex
  HEADER_STD_COMPLETE_REGEX = [
    ['cstdio',         false, true , R[F['s?scanf', 'puts', 's?printf', 'f?gets', '(?:get|put)char', 'getc'], C['FILE','std(?:in|out|err)','EOF']] ],
    ['cassert',        false, true , R[F['assert']] ],
    ['cstring',        false, true , R[F['mem(?:cpy|set|n?cmp)', 'str(?:len|n?cmp|n?cpy|error|cat|str|chr)']] ],
    ['cstdlib',        false, true , R[F['system','abs','ato[if]', 'itoa', 'strto[dflu]+','free','exit','l?abs','s?rand(?:_r|om)?','qsort'], C['EXIT_[A-Z]*', 'NULL']] ],
    ['cmath',          false, true , R[F['pow[fl]?','a?(?:sin|cos|tan)[hl]*', 'atan2[fl]?', 'exp[m12fl]*', 'fabs[fl]?', 'log[210fl]+', 'nan[fl]?', '(?:ceil|floor)[fl]?', 'l?l?round[fl]?', 'sqrt[fl]?'], C['M_[A-Z24_]*', 'NAN', 'INFINITY', 'HUGE_[A-Z]*']] ],
    ['strings.h',      false, true , R[F['b(?:cmp|copy|zero)', 'strn?casecmp']] ],
    ['typeinfo',       false, true , R[C['typeid']] ],
    ['new',            true , true , R[F['set_new_handler'], C['nothrow']] ],
    ['limits',         true , true , R[T['numeric_limits']] ],
    ['algorithm',      true , true , R[F['(?:stable_|partial_)?sort(?:_copy)?', 'unique(?:_copy)?', 'reverse(?:_copy)?', 'nth_element', '(?:lower|upper)_bound', 'binary_search', '(?:prev|next)_permutation', 'min', 'max', 'count', 'random_shuffle', 'swap']] ],
    ['numeric',        true , true , R[F['partial_sum', 'accumulate', 'adjacent_difference', 'inner_product']] ],
    ['iostream',       true , true , R[C['c(?:err|out|in)']] ],
    ['sstream',        true , true , R[C['[io]?stringstream']] ],
    ['bitset',         true , true , R[T['bitset']] ],
    ['complex',        true , true , R[T['complex']] ],
    ['deque',          true , true , R[T['deque']] ],
    ['queue',          true , true , R[T['queue','priority_queue']] ],
    ['list',           true , true , R[T['list']] ],
    ['map',            true , true , R[T['(?:multi)?map']] ],
    ['set',            true , true , R[T['(?:multi)?set']] ],
    ['vector',         true , true , R[T['vector']] ],
    ['iomanip',        true , true , R[F['setprecision', 'setbase', 'setw'], C['fixed', 'hex']]],
    ['fstream',        true , true , R[T['fstream']] ],
    ['ctime',          false, true , R[F['time', 'clock'], C['CLOCKS_PER_SEC']]],
    ['string',         true , true , R[C['string']] ],
    ['utility',        true , true , R[T['pair'], F['make_pair']] ],
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
          has_keyword = (has_header && !complete) || (content =~ regex)
          use_std ||= std && has_keyword

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
