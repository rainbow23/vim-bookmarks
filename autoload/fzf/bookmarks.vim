""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" color functions
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function! s:get_color(attr, ...)
    let gui = has('termguicolors') && &termguicolors
    let fam = gui ? 'gui' : 'cterm'
    let pat = gui ? '^#[a-f0-9]\+' : '^[0-9]\+$'
    for group in a:000
        let code = synIDattr(synIDtrans(hlID(group)), a:attr, fam)
        if code =~? pat
            return code
        endif
    endfor
    return ''
endfunction

if &t_Co == 256
    let s:ansi = {'black': 234, 'red': 196, 'green': 46, 'yellow': 226, 'blue': 63, 'magenta': 201, 'cyan': 117}
elseif &t_Co == 16
    let s:ansi = {'black': 0, 'red': 9, 'green': 10, 'yellow': 11, 'blue': 12, 'magenta': 13, 'cyan': 14}
else
    let s:ansi = {'black': 0, 'red': 1, 'green': 2, 'yellow': 3, 'blue': 4, 'magenta': 5, 'cyan': 6}
endif

function! s:csi(color, fg)
    let prefix = a:fg ? '38;' : '48;'
    if a:color[0] == '#'
        return prefix.'2;'.join(map([a:color[1:2], a:color[3:4], a:color[5:6]], 'str2nr(v:val, 16)'), ';')
    endif
    return prefix.'5;'.a:color
endfunction

function! s:ansi(str, group, default, ...)
    let fg = s:get_color('fg', a:group)
    let bg = s:get_color('bg', a:group)
    let color = s:csi(empty(fg) ? s:ansi[a:default] : fg, 1) .
                \ (empty(bg) ? '' : s:csi(bg, 0))
    return printf("\x1b[%s%sm%s\x1b[m", color, a:0 ? ';1' : '', a:str)
endfunction

for s:color_name in keys(s:ansi)
    execute "function! s:".s:color_name."(str, ...)\n"
                \ "  return s:ansi(a:str, get(a:, 1, ''), '".s:color_name."')\n"
                \ "endfunction"
endfor


""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" format functions
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function! s:pad(t, n)
    if len(a:t) > a:n
        return a:t[:(a:n-1)]."…"
    else
        let spaces = a:n - len(a:t)
        let spaces = printf("%".spaces."s", "")
        return a:t.spaces
    endif
endfunction

function! s:is_annotation(t)
    if a:t =~ "^Annotation: " | return s:green("§ ".a:t[12:]) | endif
endfunction

function! s:format_text(t, f)
    """Format second column with text and filename."""
    let text = a:t | let fname = a:f

    " strip leading spaces and tabs
    let text = substitute(text, "^ *", "", "")
    let text = substitute(text, "^\t*", "", "")

    " when colorizing text, the actual string will be longer than the one
    " that is showed, store the difference and add it to the padding
    let slen = len(text)
    let text = substitute(text, "\t", s:cyan("\\\\t"), "g")
    let diff = len(text) - slen

    let annotation = s:is_annotation(text) | let slen = len(text)
    if !empty(annotation) | let text = annotation | let diff = len(text) - slen + 10 | endif

    return s:preview? [s:pad(text, 60), !empty(annotation)] : s:pad(text, 60+diff)."\t".s:cyan(fname)
endfunction

function! s:format_line(b)
    """Format fzf line."""

    let list = []
    let line = split(a:b, ":")
    let fname = fnamemodify(line[0], ":.") | let lnr = line[1] | let text = join(line[2:], ":")

    " colon in fname? it would mess up the line, skip it
    if !filereadable(fname) | return '' | endif
    let text = s:format_text(text, fname)

    if s:preview
        let text = text[1]? "\t".text[0] : ''
        return s:yellow(fname).":".lnr.text
    else
        return s:yellow(lnr)."\t".text
    endif
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" fzf functions
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function! fzf#bookmarks#open(line)
    let line = split(a:line, "\t")

    if s:preview
        let fnameAndLnr = split(line[0], ":")
        let fname = fnameAndLnr[0] | let lnr = fnameAndLnr[1]
    else
        let fname = line[2] | let lnr = line[0]
    endif

    if bufname(bufnr("%")) !=# fname | execute "e ".fname | endif
    execute "normal! ".lnr."gg"
endfunction

" a:preview = 1 現在開いているファイルのみ対象
" a:preview = 3 git管理しているファイルが対象
function! fzf#bookmarks#list(preview)
    """Show a list of current bookmarks."""

    let list = [] | let s:preview = a:preview

    for b in bm#location_list()
      " echo b
      " /Users/goodscientist1023/dotfiles/_vimrc:1:Annotation: one

      let path = split(b,":")
      " /Users/goodscientist1023/dotfiles/_vimrc

      let line  = ""

      "  a:preview = 1 全てのファイルをリストにする
      if a:preview == 1
        let line = s:format_line(b)

      " a:preview = 2 現在開いているファイルのみ対象
      elseif a:preview == 2
        let path             = split(b,":")
        let currfilefullpath = expand('%:p')
        if(currfilefullpath == path[0])
          let line = s:format_line(b)
        endif

      " a:preview = 3 git管理しているファイルが対象
      elseif a:preview == 3
        let path             = split(b,":")
        let bmPathWords      = split(path[0],"/")
        let rootGitPathWords = split(MoshGitPath(),"/")
        let isMatchWord      = 0
        let index            = 0

        while index < len(rootGitPathWords)
          " パスの単語が一致する場合、
          " 現在開いているファイルのgit管理なのでプレビューに含める
          if match("^" . rootGitPathWords[index], bmPathWords[index]) == 1
            let isMatchWord = 1
          else
            let isMatchWord = 0
            break
          endif
          let index += 1
        endwhile

        if isMatchWord  == 1
          let line = s:format_line(b)
        endif
      endif

      if line != '' | call add(list, line) | endif
    endfor
    return list
endfunction

" https://stackoverflow.com/questions/30171512/how-to-set-the-root-of-git-repository-to-vi-vim-find-path
function! MoshGitPath()
  let g:gitdir=substitute(system("git rev-parse --show-toplevel 2>&1 | grep -v fatal:"),'\n','','g')
  if  g:gitdir != '' && isdirectory(g:gitdir) && index(split(&path, ","),g:gitdir) < 0
    return g:gitdir
  endif
endfunction

