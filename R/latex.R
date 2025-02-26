#' Compile a LaTeX document
#'
#' The function \code{latexmk()} emulates the system command \command{latexmk}
#' (\url{https://ctan.org/pkg/latexmk}) to compile a LaTeX document. The
#' functions \code{pdflatex()}, \code{xelatex()}, and \code{lualatex()} are
#' wrappers of \code{latexmk(engine =, emulation = TRUE)}.
#'
#' The \command{latexmk} emulation works like this: run the LaTeX engine once
#' (e.g., \command{pdflatex}), run \command{makeindex} to make the index if
#' necessary (the \file{*.idx} file exists), run the bibliography engine
#' \command{bibtex} or \command{biber} to make the bibliography if necessary
#' (the \file{*.aux} or \file{*.bcf} file exists), and finally run the LaTeX
#' engine a number of times (the maximum is 10 by default) to resolve all
#' cross-references.
#'
#' If \code{emulation = FALSE}, you need to make sure the executable
#' \command{latexmk} is available in your system, otherwise \code{latexmk()}
#' will fall back to \code{emulation = TRUE}. You can set the global option
#' \code{options(tinytex.latexmk.emulation = FALSE)} to always avoid emulation
#' (i.e., always use the executable \command{latexmk}).
#'
#' The default command to generate the index (if necessary) is
#' \command{makeindex}. To change it to a different command (e.g.,
#' \command{zhmakeindex}), you may set the global option
#' \code{tinytex.makeindex}. To pass additional command-line arguments to the
#' command, you may set the global option \code{tinytex.makeindex.args} (e.g.,
#' \code{options(tinytex.makeindex = 'zhmakeindex', tinytex.makeindex.args =
#' c('-z', 'pinyin'))}).
#'
#' If you are using the LaTeX distribution TinyTeX, but its path is not in the
#' \code{PATH} variable of your operating system, you may set the global option
#' \code{tinytex.tlmgr.path} to the full path of the executable \command{tlmgr},
#' so that \code{latexmk()} knows where to find executables like
#' \command{pdflatex}. For example, if you are using Windows and your TinyTeX is
#' on an external drive \file{Z:/} under the folder \file{TinyTeX}, you may set
#' \code{options(tinytex.tlmgr.path = "Z:/TinyTeX/bin/win32/tlmgr.bat")}.
#' Usually you should not need to set this option because TinyTeX can add itself
#' to the \code{PATH} variable during installation or via
#' \code{\link{use_tinytex}()}. In case both methods fail, you can use this
#' manual approach.
#' @param file A LaTeX file path.
#' @param engine A LaTeX engine (can be set in the global option
#'   \code{tinytex.engine}, e.g., \code{options(tinytex.engine = 'xelatex')}).
#' @param bib_engine A bibliography engine (can be set in the global option
#'   \code{tinytex.bib_engine}).
#' @param engine_args Command-line arguments to be passed to \code{engine} (can
#'   be set in the global option \code{tinytex.engine_args}, e.g.,
#'   \code{options(tinytex.engine_args = '-shell-escape'}).
#' @param emulation Whether to emulate the executable \command{latexmk} using R.
#' @param max_times The maximum number of times to rerun the LaTeX engine when
#'   using emulation. You can set the global option
#'   \code{tinytex.compile.max_times}, e.g.,
#'   \code{options(tinytex.compile.max_times = 3)}.
#' @param install_packages Whether to automatically install missing LaTeX
#'   packages found by \code{\link{parse_packages}()} from the LaTeX log. This
#'   argument is only for the emulation mode and TeX Live.
#' @param pdf_file Path to the PDF output file. By default, it is under the same
#'   directory as the input \code{file} and also has the same base name. When
#'   \code{engine == 'latex'}, this will be a DVI file.
#' @param clean Whether to clean up auxiliary files after compilation (can be
#'   set in the global option \code{tinytex.clean}, which defaults to
#'   \code{TRUE}).
#' @export
#' @return A character string of the path of the output file (i.e., the value of
#'   the \code{pdf_file} argument).
latexmk = function(
  file, engine = c('pdflatex', 'xelatex', 'lualatex', 'latex'),
  bib_engine = c('bibtex', 'biber'), engine_args = NULL, emulation = TRUE,
  max_times = 10, install_packages = emulation && tlmgr_available(),
  pdf_file = gsub('tex$', 'pdf', file), clean = TRUE
) {
  if (!grepl('[.]tex$', file))
    stop("The input file '", file, "' does not have the .tex extension")
  file = path.expand(file)
  if (missing(engine)) engine = getOption('tinytex.engine', engine)
  engine = gsub('^(pdf|xe|lua)(tex)$', '\\1la\\2', engine)  # normalize *tex to *latex
  engine = match.arg(engine)
  is_latex = engine == 'latex'
  tweak_path()
  if (missing(emulation)) emulation = getOption('tinytex.latexmk.emulation', emulation)
  if (!emulation) {
    if (Sys.which('latexmk') == '') {
      warning('The executable "latexmk" not found in your system')
      emulation = TRUE
    } else if (system2_quiet('latexmk', '-v') != 0) {
      warning('The executable "latexmk" was found but does not work')
      emulation = TRUE
    }
  }
  if (missing(max_times)) max_times = getOption('tinytex.compile.max_times', max_times)
  if (missing(bib_engine)) bib_engine = getOption('tinytex.bib_engine', bib_engine)
  if (missing(engine_args)) engine_args = getOption('tinytex.engine_args', engine_args)
  if (missing(clean)) clean = getOption('tinytex.clean', TRUE)
  pdf = gsub('tex$', if (is_latex) 'dvi' else 'pdf', basename(file))
  if (!is.null(output_dir <- getOption('tinytex.output_dir'))) {
    output_dir_arg = shQuote(paste0(if (emulation) '-', '-output-directory=', output_dir))
    if (length(grep(output_dir_arg, engine_args, fixed = TRUE)) == 0) stop(
      "When you set the global option 'tinytex.output_dir', the argument 'engine_args' ",
      "must contain this value: ", capture.output(dput(output_dir_arg))
    )
    pdf = file.path(output_dir, pdf)
    if (missing(pdf_file)) pdf_file = file.path(output_dir, basename(pdf_file))
  }
  if (is_latex) pdf_file = with_ext(pdf_file, 'dvi')
  check_pdf = function() {
    if (!file.exists(pdf)) show_latex_error(file, with_ext(pdf, 'log'), TRUE)
    file_rename(pdf, pdf_file)
    pdf_file
  }
  if (emulation) {
    latexmk_emu(file, engine, bib_engine, engine_args, max_times, install_packages, clean)
    return(check_pdf())
  }
  system2_quiet('latexmk', c(
    '-latexoption=-halt-on-error -interaction=batchmode',
    if (is_latex) '-latex=latex' else paste0('-pdf -pdflatex=', engine),
    engine_args, shQuote(file)
  ), error = {
    if (install_packages) warning(
      'latexmk(install_packages = TRUE) does not work when emulation = FALSE'
    )
    check_latexmk_version()
  })
  if (clean) system2('latexmk', c('-c', engine_args), stdout = FALSE)
  check_pdf()
}

#' @param ... Arguments to be passed to \code{latexmk()} (other than
#'   \code{engine} and \code{emulation}).
#' @rdname latexmk
#' @export
pdflatex = function(...) latexmk(engine = 'pdflatex', emulation = TRUE, ...)

#' @rdname latexmk
#' @export
xelatex  = function(...) latexmk(engine = 'xelatex',  emulation = TRUE, ...)

#' @rdname latexmk
#' @export
lualatex = function(...) latexmk(engine = 'lualatex', emulation = TRUE, ...)

# a quick and dirty version of latexmk (should work reasonably well unless the
# LaTeX document is extremely complicated)
latexmk_emu = function(
  file, engine, bib_engine = c('bibtex', 'biber'), engine_args = NULL, times = 10,
  install_packages = FALSE, clean
) {
  # note that the order of the extensions below matters; don't rearrange them
  aux = c(
    'log', 'idx', 'aux', 'bcf', 'blg', 'bbl', 'fls', 'out', 'lof', 'lot', 'toc',
    'nav', 'snm', 'vrb', 'ilg', 'ind', 'xwm', 'brf', 'run.xml'
  )
  base = gsub('[.]tex$', '', basename(file))
  aux_files = paste(base, aux, sep = '.')
  aux_files = c(aux_files, 'preview.aux')  # generated by the preview package
  if (!is.null(output_dir <- getOption('tinytex.output_dir')))
    aux_files = file.path(output_dir, aux_files)
  logfile = aux_files[1]; unlink(logfile)  # clean up the log before compilation

  # clean up aux files from LaTeX compilation
  files1 = exist_files(aux_files)
  keep_log = FALSE
  on.exit({
    files2 = exist_files(aux_files)
    files3 = setdiff(files2, files1)
    if (keep_log || length(latex_warning(logfile, TRUE))) files3 = setdiff(files3, logfile)
    if (clean) unlink(files3)
  }, add = TRUE)

  pkgs_last = character()
  filep = sub('.log$', if (engine == 'latex') '.dvi' else '.pdf', logfile)
  run_engine = function() {
    on_error  = function() {
      if (install_packages && file.exists(logfile)) {
        pkgs = parse_packages(logfile, quiet = c(TRUE, FALSE, FALSE))
        if (length(pkgs) && !identical(pkgs, pkgs_last)) {
          message('Trying to automatically install missing LaTeX packages...')
          if (tlmgr_install(pkgs) == 0) {
            pkgs_last <<- pkgs
            return(run_engine())
          }
        }
      }
      keep_log <<- TRUE
      show_latex_error(file, logfile)
    }
    res = system2_quiet(
      engine, c('-halt-on-error', '-interaction=batchmode', engine_args, shQuote(file)),
      error = on_error(), logfile = logfile, fail_rerun = getOption('tinytex.verbose', FALSE)
    )
    # PNAS you are the worst! Why don't you singal an error in case of missing packages?
    if (res == 0 && !file.exists(filep)) on_error()
    invisible(res)
  }
  run_engine()
  if (install_packages) check_babel(logfile)
  # generate index
  if (file.exists(idx <- aux_files[2])) {
    idx_engine = getOption('tinytex.makeindex', 'makeindex')
    system2_quiet(idx_engine, c(getOption('tinytex.makeindex.args'), shQuote(idx)), error = {
      stop("Failed to build the index via ", idx_engine, call. = FALSE)
    })
  }
  # generate bibliography
  bib_engine = match.arg(bib_engine)
  if (install_packages && bib_engine == 'biber' && Sys.which('biber') == '')
    tlmgr_install('biber')
  aux = aux_files[if ((biber <- bib_engine == 'biber')) 4 else 3]
  if (file.exists(aux)) {
    if (biber || require_bibtex(aux)) {
      blg = aux_files[5]  # bibliography log file
      build_bib = function() system2_quiet(bib_engine, shQuote(aux), error = {
        stop("Failed to build the bibliography via ", bib_engine, call. = FALSE)
      })
      build_bib()
      check_blg = function() {
        if (!file.exists(blg)) return(TRUE)
        x = readLines(blg)
        if (length(grep('error message', x)) == 0) return(TRUE)
        warn = function() {
          warning(
            bib_engine, ' seems to have failed:\n\n', paste(x, collapse = '\n'),
            call. = FALSE
          )
          TRUE
        }
        if (!tlmgr_available() || !install_packages) return(warn())
        # install the possibly missing .bst package and rebuild bib
        r = '.* open style file ([^ ]+).*'
        pkgs = parse_packages(files = gsub(r, '\\1', grep(r, x, value = TRUE)))
        if (length(pkgs) == 0) return(warn())
        tlmgr_install(pkgs); build_bib()
        FALSE
      }
      # check .blg at most 3 times for missing packages
      for (i in 1:3) if (check_blg()) break
    }
  }
  for (i in seq_len(times)) {
    if (file.exists(logfile)) {
      if (!needs_rerun(logfile)) break
    } else warning('The LaTeX log file "', logfile, '" is not found')
    run_engine()
  }
}

require_bibtex = function(aux) {
  x = readLines(aux)
  r = length(grep('^\\\\citation\\{', x)) && length(grep('^\\\\bibdata\\{', x)) &&
    length(grep('^\\\\bibstyle\\{', x))
  if (r && !tlmgr_available() && os == 'windows') tweak_aux(aux, x)
  r
}

# remove the .bib extension in \bibdata{} in the .aux file, because bibtex on
# Windows requires no .bib extension (sigh)
tweak_aux = function(aux, x = readLines(aux)) {
  r = '^\\\\bibdata\\{.+\\}\\s*$'
  if (length(i <- grep(r, x)) == 0) return()
  x[i] = gsub('[.]bib([,}])', '\\1', x[i])
  writeLines(x, aux)
}

needs_rerun = function(log) {
  any(grepl(
    '(Rerun to get |Please \\(re\\)run | Rerun LaTeX\\.)', readLines(log),
    useBytes = TRUE
  ))
}

system2_quiet = function(..., error = NULL, logfile = NULL, fail_rerun = TRUE) {
  # system2(stdout = FALSE) fails on Windows with MiKTeX's pdflatex in the R
  # console in RStudio: https://github.com/rstudio/rstudio/issues/2446 so I have
  # to redirect stdout and stderr to files instead
  f1 = tempfile('stdout'); f2 = tempfile('stderr')
  on.exit(unlink(c(f1, f2)), add = TRUE)

  # run the command quietly if possible
  res = system2(..., stdout = if (use_file_stdout()) f1 else FALSE, stderr = f2)
  if (is.character(logfile) && file.exists(f2) && length(e <- xfun::read_utf8(f2))) {
    i = grep('^\\s*$', e, invert = TRUE)
    e[i] = paste('!', e[i])  # prepend ! to non-empty error messages
    cat('', e, file = logfile, sep = '\n', append = TRUE)
  }

  # if failed, use the normal mode
  if (fail_rerun && res != 0) res = system2(...)
  # if still fails, run the error callback
  if (res != 0) error  # lazy evaluation
  invisible(res)
}

use_file_stdout = function() {
  getOption('tinytex.stdout.file', {
    os == 'windows' && interactive() && !is.na(Sys.getenv('RSTUDIO', NA))
  })
}

# parse the LaTeX log and show error messages
show_latex_error = function(
  file, logfile = gsub('[.]tex$', '.log', basename(file)), force = FALSE
) {
  e = c('Failed to compile ', file, '. See https://yihui.name/tinytex/r/#debugging for debugging tips.')
  if (!file.exists(logfile)) stop(e, call. = FALSE)
  x = readLines(logfile, warn = FALSE)
  b = grep('^\\s*$', x)  # blank lines
  b = c(b, which(x == "Here is how much of TeX's memory you used:"))
  m = NULL
  for (i in grep('^! ', x)) {
    # ignore the last error message about the fatal error
    if (grepl('==> Fatal error occurred', x[i], fixed = TRUE)) next
    n = b[b > i]
    n = if (length(n) == 0) i else min(n) - 1L
    m = c(m, x[i:n], '')
  }
  if (length(m)) {
    message(paste(m, collapse = '\n'))
    latex_hints(m, file)
    stop(e, ' See ', logfile, ' for more info.', call. = FALSE)
  } else if (force) stop(e, call. = FALSE)
}

latex_hints = function(x, f) {
  check_inline_math(x, f)
  check_unicode(x)
}

check_inline_math = function(x, f) {
  r = 'l[.][0-9]+\\s*|\\s*[0-9.]+\\\\times.*'
  if (!any('! Missing $ inserted.' == x) || !length(i <- grep(r, x))) return()
  m = gsub(r, '', x[i]); m = m[m != '']
  s = xfun::with_ext(f, 'Rmd')
  if (file.exists(s)) message(
    if (length(m)) c('Try to find the following text in ', s, ':\n', paste(' ', m, '\n'), '\n'),
    'You may need to add $ $ around a certain inline R expression `r ` in ', s,
    if (length(m)) ' (see the above hint)',
    '. See https://github.com/rstudio/rmarkdown/issues/385 for more info.'
  )
}

check_unicode = function(x) {
  if (length(grep('! Package inputenc Error: Unicode character', x))) message(
    'Try other LaTeX engines instead (e.g., xelatex) if you are using pdflatex. ',
    'For R Markdown users, see https://bookdown.org/yihui/rmarkdown/pdf-document.html'
  )
}

# whether a LaTeX log file contains LaTeX or package (e.g. babel) warnings
latex_warning = function(file, show = FALSE) {
  if (!file.exists(file)) return()
  x = readLines(file, warn = FALSE)
  if (length(i <- grep('^(LaTeX|Package [[:alnum:]]+) Warning:', x)) == 0) return()
  # these warnings may be okay (our Pandoc LaTeX template in rmarkdown may need an update)
  i = i[grep('^Package (fixltx2e|caption|hyperref) Warning:', x[i], invert = TRUE)]
  if (length(i) == 0) return()
  b = grep('^\\s*$', x)
  i = unlist(lapply(i, function(j) {
    n = b[b > j]
    n = if (length(n) == 0) i else min(n) - 1L
    j:n
  }))
  i = sort(unique(i))
  if (show) warning(paste(x[i], collapse = '\n'), call. = FALSE)
  x[i]
}

# check if any babel packages are missing
check_babel = function(file) {
  if (length(m <- latex_warning(file)) == 0 || length(grep('^Package babel Warning:', m)) == 0)
    return()
  r = "^\\(babel).* language `([[:alpha:]]+)'.*$"
  if (length(i <- grep(r, m)) == 0) return()
  tlmgr_install(paste0('hyphen-', tolower(gsub(r, '\\1', m[i]))))
}

# check the version of latexmk
check_latexmk_version = function() {
  out = system2('latexmk', '-v', stdout = TRUE)
  reg = '^.*Version (\\d+[.]\\d+).*$'
  out = grep(reg, out, value = TRUE)
  if (length(out) == 0) return()
  ver = as.numeric_version(gsub(reg, '\\1', out[1]))
  if (ver >= '4.43') return()
  system2('latexmk', '-v')
  warning(
    'Your latexmk version seems to be too low. ',
    'You may need to update the latexmk package or your LaTeX distribution.',
    call. = FALSE
  )
}

# return file paths that exist
exist_files = function(files) {
  files[utils::file_test('-f', files)]
}

# use file.copy() if file.rename() fails
file_rename = function(from, to) {
  if (from == to) return(TRUE)
  if (!suppressWarnings(file.rename(from, to))) {
    if (file.copy(from, to, overwrite = TRUE)) file.remove(from)
  }
}

#' Find missing LaTeX packages from a LaTeX log file
#'
#' Analyze the error messages in a LaTeX log file to figure out the names of
#' missing LaTeX packages that caused the errors. These packages can be
#' installed via \code{\link{tlmgr_install}()}. Searching for missing packages
#' is based on \code{\link{tlmgr_search}()}.
#' @param log Path to the LaTeX log file (typically named \file{*.log}).
#' @param text A character vector of the error log (read from the file provided
#'   by the \code{log} argument by default).
#' @param files A character vector of names of the missing files (automatically
#'   detected from the \code{log} by default).
#' @param quiet Whether to suppress messages when finding packages. It should be
#'   a logical vector of length 3: the first element indicates whether to
#'   suppress the message when no missing LaTeX packages could be detected from
#'   the log, the second element indicate whether to suppress the message when
#'   searching for packages via \code{tlmgr_search()}, and the third element
#'   indicates whether to warn if no packages could be found via
#'   \code{tlmgr_search()}.
#' @return A character vector of LaTeX package names.
#' @export
parse_packages = function(
  log, text = readLines(log), files = detect_files(text), quiet = rep(FALSE, 3)
) {
  pkgs = character(); quiet = rep_len(quiet, length.out = 3)
  x = unique(c(files, miss_font()))
  if (length(x) == 0) {
    if (!quiet[1]) message(
      'I was unable to find any missing LaTeX packages from the error log',
      if (missing(log)) '.' else c(' ', log, '.')
    )
    return(invisible(pkgs))
  }
  for (j in seq_along(x)) {
    l = tlmgr_search(paste0('/', x[j]), stdout = TRUE, .quiet = quiet[2])
    if (length(l) == 0) next
    if (x[j] == 'fandol') return(x[j])  # a known package
    # why $? e.g. searching for mf returns a list like this
    # metafont.x86_64-darwin:
    #     bin/x86_64-darwin/mf       <- what we want
    # metapost.x86_64-darwin:
    #     bin/x86_64-darwin/mfplain  <- but this also matches /mf
    k = grep(paste0('/', x[j], '$'), l)  # only match /mf exactly
    if (length(k) == 0) {
      if (!quiet[3]) warning('Failed to find a package that contains ', x[j])
      next
    }
    k = k[k > 2]
    p = grep(':$', l)
    if (length(p) == 0) next
    for (i in k) {
      pkg  = gsub(':$', '', l[max(p[p < i])])  # find the package name
      pkgs = c(pkgs, setNames(pkg, x[j]))
    }
  }
  pkgs = gsub('[.].*', '', pkgs)  # e.g., 'metafont.x86_64-darwin'
  unique(pkgs)
}

# find filenames (could also be font names) from LaTeX error logs
detect_files = function(text) {
  # possible errors are like:
  # ! LaTeX Error: File `framed.sty' not found.
  # /usr/local/bin/mktexpk: line 123: mf: command not found
  # ! Font U/psy/m/n/10=psyr at 10.0pt not loadable: Metric (TFM) file not found
  # !pdfTeX error: /usr/local/bin/pdflatex (file tcrm0700): Font tcrm0700 at 600 not found
  # xdvipdfmx:fatal: Unable to find TFM file "rsfs10"
  # ! The font "FandolSong-Regular" cannot be found.
  # ! Package babel Error: Unknown option `ngerman'. Either you misspelled it
  # (babel)                or the language definition file ngerman.ldf was not found.
  # !pdfTeX error: pdflatex (file 8r.enc): cannot open encoding file for reading
  # ! CTeX fontset `fandol' is unavailable in current mode
  # Package widetext error: Install the flushend package which is a part of sttools
  # Package biblatex Info: ... file 'trad-abbrv.bbx' not found
  # ! Package pdftex.def Error: File `logo-mdpi-eps-converted-to.pdf' not found
  # ! Package tikz Error: I did not find the tikz library 'hobby'... named tikzlibraryhobby.code.tex
  # support file `supp-pdf.mkii' (supp-pdf.tex) is missing
  r = c(
    ".*! Font [^=]+=([^ ]+).+ not loadable.*",
    '.*! .*The font "([^"]+)" cannot be found.*',
    '.*!.+ error:.+\\(file ([^)]+)\\): .*',
    '.*Package widetext error: Install the ([^ ]+) package.*',
    '.*Unable to find TFM file "([^"]+)".*',
    # the above are messages about missing fonts; below are typically missing .sty or commands

    ".* File `(.+eps-converted-to.pdf)'.*",
    ".*! LaTeX Error: File `([^']+)' not found.*",
    ".* file '([^']+)' not found.*",
    '.*the language definition file ([^ ]+) .*',
    '.* \\(file ([^)]+)\\): cannot open .*',
    ".*file `([^']+)' .*is missing.*",
    ".*! CTeX fontset `([^']+)' is unavailable.*",
    '.* (tikzlibrary[^.]+[.]code[.]tex).*',
    ".*: ([^:]+): command not found.*"
  )
  x = grep(paste(r, collapse = '|'), text, value = TRUE)
  if (length(x) > 0) unique(unlist(lapply(r, function(p) {
    z = grep(p, x, value = TRUE)
    v = gsub(p, '\\1', z)
    if (length(v) == 0) return(v)
    if (!(p %in% r[1:5])) return(if (p == r[6]) 'epstopdf' else v)
    if (p == r[4]) paste0(v, '.sty') else font_ext(v)
  })))
}

# a helper function that combines parse_packages() and tlmgr_install()
parse_install = function(...) {
  tlmgr_install(parse_packages(...))
}

# check missfont.log and detect the missing font packages
miss_font = function() {
  if (!file.exists(f <- 'missfont.log')) return()
  on.exit(unlink(f), add = TRUE)
  x = gsub('\\s*$', '', readLines(f))
  x = unique(gsub('.+\\s+', '', x))
  if (length(x)) font_ext(x)
}

font_ext = function(x) {
  i = !grepl('[.]', x)
  x[i] = paste0(x[i], '[.](tfm|afm|mf|otf)')
  x
}

# it should be rare that we need to manually run texhash
texhash = function() {
  tweak_path()
  system2('texhash')
}

updmap = function(usermode = FALSE) {
  tweak_path()
  system2(if (usermode) 'updmap-user' else 'updmap-sys')
}

fmtutil = function(usermode = FALSE) {
  tweak_path()
  system2(if (usermode) 'fmtutil-user' else 'fmtutil-sys', '--all')
}

fc_cache = function(args = c('-v', '-r')) {
  tweak_path()
  system2('fc-cache', args)
}

# look up files in the Kpathsea library, e.g., kpsewhich('Sweave.sty')
kpsewhich = function(filename, options = character()) {
  tweak_path()
  system2('kpsewhich', c(options, shQuote(filename)))
}
