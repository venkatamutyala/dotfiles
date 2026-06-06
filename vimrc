" Don't try to be vi compatible
set nocompatible

" Helps force plugins to load correctly when it is turned back on below
filetype off

" TODO: Load plugins here (pathogen or vundle)

" Turn on syntax highlighting
syntax on

" For plugins to load correctly
filetype plugin indent on

" TODO: Pick a leader key
" let mapleader = ","

" Security
set modelines=0

" Show line numbers
set number

" Show file stats
set ruler

" Blink cursor on error instead of beeping (grr)
set visualbell

" Encoding
set encoding=utf-8

" Whitespace
set wrap
set textwidth=79
set formatoptions=tcqrn1
set tabstop=2
set shiftwidth=2
set softtabstop=2
set expandtab
set noshiftround

" Cursor motion
set scrolloff=3
set backspace=indent,eol,start
set matchpairs+=<:> " use % to jump between pairs
runtime! macros/matchit.vim

" Move up/down editor lines
nnoremap j gj
nnoremap k gk

" Allow hidden buffers
set hidden

" Rendering
set ttyfast

" Status bar
set laststatus=2

" Last line
set showmode
set showcmd

" Searching
nnoremap / /\v
vnoremap / /\v
set hlsearch
set incsearch
set ignorecase
set smartcase
set showmatch
" clear search highlight (trailing comments on :map become part of the mapping)
map <leader><space> :let @/=''<cr>

" Remap help key.
inoremap <F1> <ESC>:set invfullscreen<CR>a
nnoremap <F1> :set invfullscreen<CR>
vnoremap <F1> :set invfullscreen<CR>

" Textmate holdouts

" Formatting
map <leader>q gqip

" Visualize tabs and newlines
set listchars=tab:▸\ ,eol:¬
" Uncomment this to enable by default:
" set list " To enable by default
" Or use your leader key + l to toggle on/off
" Toggle tabs and EOL display
map <leader>l :set list!<CR>

" Color scheme (terminal)
set t_Co=256
set background=dark
let g:solarized_termcolors=256
let g:solarized_termtrans=1
" put https://raw.github.com/altercation/vim-colors-solarized/master/colors/solarized.vim
" in ~/.vim/colors/ and uncomment:
" colorscheme solarized


" Plugins pinned to commits that were latest as of 2026-05-07 (reproducible installs).
call plug#begin()
Plug 'preservim/NERDTree',          { 'commit': '690d061b591525890f1471c6675bcb5bdc8cdff9' }
Plug 'hashivim/vim-terraform',      { 'commit': '520498fab16a3a11f2ae1b8cb65e0a1684bc317a' }
Plug 'https://tpope.io/vim/fugitive.git', { 'commit': '3b753cf8c6a4dcde6edee8827d464ba9b8c4a6f0' }
Plug 'suan/vim-instant-markdown',   { 'commit': 'e62da3d05500c0cce24f498e5c1184fe99cbe231' }
Plug 'pearofducks/ansible-vim',     { 'commit': '9e020fbb31b4959ea12d97afa78a90c7528ac109' }
Plug 'hdima/python-syntax',         { 'commit': '69760cb3accce488cc072772ca918ac2cbf384ba' }
Plug 'junegunn/fzf',                { 'commit': '263eb4732fc6268f9fb35cffb634903ea8e2a26b', 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim',            { 'commit': 'b9624aa012ddcbae9e79964bfd30cc1fbe3cf263' }
Plug 'tpope/vim-eunuch',            { 'commit': 'e86bb794a1c10a2edac130feb0ea590a00d03f1e' }
Plug 'morhetz/gruvbox',             { 'commit': '697c00291db857ca0af00ec154e5bd514a79191f' }
call plug#end()


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" => Nerd Tree
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
let g:NERDTreeWinPos = "left"
let NERDTreeShowHidden=0
let NERDTreeIgnore = ['\.pyc$', '__pycache__']
let g:NERDTreeWinSize=35
map <leader>nn :NERDTreeToggle<cr>
map <leader>nb :NERDTreeFromBookmark<Space>
map <leader>nf :NERDTreeFind<cr>




autocmd vimenter * ++nested silent! colorscheme gruvbox
