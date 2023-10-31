" Minimal Vim configuration

set encoding=utf-8
scriptencoding utf-8
set fileencodings+=cp932,enc-jp

if &compatible
  set nocompatible
endif

set title
set ruler
set noshowcmd
set display=lastline
set splitbelow
set nonumber
set signcolumn=auto
set nocursorline
set pumheight=10
set laststatus=0
set tabstop=4
set softtabstop=4
set shiftwidth=4
set expandtab
set autoindent
set hlsearch
set ignorecase
set smartcase
set incsearch
set backspace=indent,eol,start
set wildmode=longest,list
set autoread
set omnifunc=syntaxcomplete#Complete
set hidden
set modeline
set completeopt=menu,menuone
set diffopt+=vertical,algorithm:histogram,indent-heuristic
set ambiwidth=double
set background=dark

if has('termguicolors')
  set termguicolors
endif

if has('win32')
  set viminfo+=n~/vimfiles/viminfo
  set directory=~/vimfiles/swap
  call mkdir(&directory, 'p')

  let s:pwsh = 'pwsh'
  let s:powershell = 'powershell'
  if executable(s:pwsh)
    let &shell = s:pwsh
  elseif executable(s:powershell)
    let &shell = s:powershell
  endif
elseif has('unix')
  set viminfo+=n~/.vim/viminfo
  set directory=~/.vim/swap
  call mkdir(&directory, 'p')

  let s:bash = '/bin/bash'
  if executable(s:bash)
    let &shell = s:bash
  endif
endif

syntax enable

filetype plugin indent on

augroup vimrc_filetype_indent
  autocmd!
  autocmd FileType json setlocal ts=2 sts=2 sw=2
  autocmd FileType yaml setlocal ts=2 sts=2 sw=2
  autocmd FileType sshconfig setlocal ts=2 sts=2 sw=2
  autocmd FileType c setlocal ts=4 sts=4 sw=4
augroup END

augroup vimrc_formatoptions
  autocmd!
  autocmd FileType * setlocal formatoptions-=ro indentkeys-=0#
augroup END
