#import "utils/utils.typ"
#import "utils/states.typ"
#import "utils/pdfpc.typ"

// touying pause mark
#let pause = [#"<touying-pause>"]
// touying meanwhile mark
#let meanwhile = [#"<touying-meanwhile>"]

// parse a sequence into content, and get the repetitions
#let _parse-content(self: utils.empty-object, need-cover: true, base: 1, index: 1, ..bodies) = {
  let bodies = bodies.pos()
  let result-arr = ()
  // repetitions
  let repetitions = base
  let max-repetitions = repetitions
  // get cover function from self
  let cover = self.methods.cover.with(self: self)
  for it in bodies {
    // if it is a function, then call it with self
    if type(it) == function {
      // subslide index
      self.subslide = index
      it = it(self)
    }
    // parse the content
    let result = ()
    let cover-arr = ()
    let children = if utils.is-sequence(it) { it.children } else { (it,) }
    for child in children {
      if child == pause {
        repetitions += 1
      } else if child == meanwhile {
        // clear the cover-arr when encounter #meanwhile
        if cover-arr.len() != 0 {
          result.push(cover(cover-arr.sum()))
          cover-arr = ()
        }
        // then reset the repetitions
        max-repetitions = calc.max(max-repetitions, repetitions)
        repetitions = 1
      } else if child == linebreak() or child == parbreak() {
        // clear the cover-arr when encounter linebreak or parbreak
        if cover-arr.len() != 0 {
          result.push(cover(cover-arr.sum()))
          cover-arr = ()
        }
        result.push(child)
      } else if type(child) == content and child.func() == list.item {
        // handle the list item
        let (conts, nextrepetitions) = _parse-content(
          self: self, need-cover: repetitions <= index, base: repetitions, index: index, child.body
        )
        let cont = conts.first()
        if repetitions <= index or not need-cover {
          result.push(list.item(cont))
        } else {
          cover-arr.push(list.item(cont))
        }
        repetitions = nextrepetitions
      } else if type(child) == content and child.func() == enum.item {
        // handle the enum item
        let (conts, nextrepetitions) = _parse-content(
          self: self, need-cover: repetitions <= index, base: repetitions, index: index, child.body
        )
        let cont = conts.first()
        if repetitions <= index or not need-cover {
          result.push(enum.item(child.at("number", default: none), cont))
        } else {
          cover-arr.push(enum.item(child.at("number", default: none), cont))
        }
        repetitions = nextrepetitions
      } else if type(child) == content and child.func() == terms.item {
        // handle the terms item
        let (conts, nextrepetitions) = _parse-content(
          self: self, need-cover: repetitions <= index, base: repetitions, index: index, child.description
        )
        let cont = conts.first()
        if repetitions <= index or not need-cover {
          result.push(terms.item(child.term, cont))
        } else {
          cover-arr.push(terms.item(child.term, cont))
        }
        repetitions = nextrepetitions
      } else {
        if repetitions <= index or not need-cover {
          result.push(child)
        } else {
          cover-arr.push(child)
        }
      }
    }
    // clear the cover-arr when end
    if cover-arr.len() != 0 {
      result.push(cover(cover-arr.sum()))
      cover-arr = ()
    }
    result-arr.push(result.sum(default: []))
  }
  max-repetitions = calc.max(max-repetitions, repetitions)
  return (result-arr, max-repetitions)
}

// touying-slide
#let touying-slide(
  self: utils.empty-object,
  repeat: auto,
  setting: body => body,
  composer: utils.side-by-side,
  section: none,
  subsection: none,
  ..bodies,
) = {
  assert(bodies.named().len() == 0, message: "unexpected named arguments:" + repr(bodies.named().keys()))
  let bodies = bodies.pos()
  let page-preamble(curr-subslide) = locate(loc => {
    if loc.page() == self.first-slide-number {
      // preamble
      utils.call-or-display(self, self.preamble)
      // pdfpc slide markers
      if self.pdfpc-file {
        pdfpc.pdfpc-file(loc)
      }
    }
    [
      #metadata((t: "NewSlide")) <pdfpc>
      #metadata((t: "Idx", v: loc.page() - 1)) <pdfpc>
      #metadata((t: "Overlay", v: curr-subslide - 1)) <pdfpc>
      #metadata((t: "LogicalSlide", v: states.slide-counter.at(loc).first())) <pdfpc>
    ]
  })
  // update states
  let _update-states(repetitions) = {
    states.slide-counter.step()
    // if section is not none, then create a new section
    let section = utils.unify-section(section)
    if section != none {
      states._new-section(short-title: section.short-title, section.title)
    }
    // if subsection is not none, then create a new subsection
    let subsection = utils.unify-section(subsection)
    if subsection != none {
      states._new-subsection(short-title: subsection.short-title, subsection.title)
    }
    // if appendix is false, then update the last-slide-counter and sections step
    if self.appendix == false {
      states.last-slide-counter.step()
      states._sections-step(repetitions)
    }
  }
  // page header and footer
  let header = utils.call-or-display(self, self.page-args.at("header", default: none))
  let footer = utils.call-or-display(self, self.page-args.at("footer", default: none))
  // for speed up, do not parse the content if repeat is none
  if repeat == none {
    return {
      header = _update-states(1) + header
      page(..(self.page-args + (header: header, footer: footer)), setting(
        page-preamble(1) + composer(..bodies)
      ))
    }
  }
  // for single page slide, get the repetitions
  if repeat == auto {
    let (_, repetitions) = _parse-content(
      self: self,
      base: 1,
      index: 1,
      ..bodies,
    )
    repeat = repetitions
  }
  if self.handout {
    let (conts, _) = _parse-content(self: self, index: repeat, ..bodies)
    header = _update-states(1) + header
    page(..(self.page-args + (header: header, footer: footer)), setting(
      page-preamble(1) + composer(..conts)
    ))
  } else {
    // render all the subslides
    let result = ()
    let current = 1
    for i in range(1, repeat + 1) {
      let new-header = header
      let (conts, _) = _parse-content(self: self, index: i, ..bodies)
      // update the counter in the first subslide
      if i == 1 {
        new-header = _update-states(repeat) + new-header
      }
      result.push(page(
        ..(self.page-args + (header: new-header, footer: footer)),
        setting(page-preamble(i) + composer(..conts)),
      ))
    }
    // return the result
    result.sum()
  }
}

// build the touying singleton
#let s = (
  // info interface
  info: (
    title: none,
    short-title: auto,
    subtitle: none,
    short-subtitle: auto,
    author: none,
    date: none,
    institution: none,
  ),
  // colors interface
  colors: (
    neutral: rgb("#303030"),
    neutral-light: rgb("#a0a0a0"),
    neutral-lighter: rgb("#d0d0d0"),
    neutral-extralight: rgb("#ffffff"),
    neutral-dark: rgb("#202020"),
    neutral-darker: rgb("#101010"),
    neutral-extradark: rgb("#000000"),
    primary: rgb("#303030"),
    primary-light: rgb("#a0a0a0"),
    primary-lighter: rgb("#d0d0d0"),
    primary-extralight: rgb("#ffffff"),
    primary-dark: rgb("#202020"),
    primary-darker: rgb("#101010"),
    primary-extradark: rgb("#000000"),
    secondary: rgb("#303030"),
    secondary-light: rgb("#a0a0a0"),
    secondary-lighter: rgb("#d0d0d0"),
    secondary-extralight: rgb("#ffffff"),
    secondary-dark: rgb("#202020"),
    secondary-darker: rgb("#101010"),
    secondary-extradark: rgb("#000000"),
    tertiary: rgb("#303030"),
    tertiary-light: rgb("#a0a0a0"),
    tertiary-lighter: rgb("#d0d0d0"),
    tertiary-extralight: rgb("#ffffff"),
    tertiary-dark: rgb("#202020"),
    tertiary-darker: rgb("#101010"),
    tertiary-extradark: rgb("#000000"),
  ),
  // handle mode
  handout: false,
  // appendix mode
  appendix: false,
  // enable pdfpc-file
  pdfpc-file: true,
  // first-slide page number, which will affect preamble,
  // default is 1
  first-slide-number: 1,
  // global preamble
  preamble: [],
  // page args
  page-args: (
    paper: "presentation-16-9",
    header: none,
    footer: align(right, states.slide-counter.display() + " / " + states.last-slide-number),
    fill: rgb("#ffffff"),
  ),
  // datetime format
  datetime-format: auto,
  // register the methods
  methods: (
    // info
    info: (self: utils.empty-object, ..args) => {
      self.info += args.named()
      self
    },
    // colors
    colors: (self: utils.empty-object, ..args) => {
      self.colors += args.named()
      self
    },
    // cover method
    cover: utils.wrap-method(hide),
    update-cover: (self: utils.empty-object, is-method: false, cover-fn) => {
      if is-method {
        self.methods.cover = cover-fn
      } else {
        self.methods.cover = utils.wrap-method(cover-fn)
      }
      self
    },
    enable-transparent-cover: (
      self: utils.empty-object, constructor: rgb, alpha: 85%) => {
      // it is based on the default cover method
      self.methods.cover = (self: utils.empty-object, body) => {
        utils.cover-with-rect(fill: utils.update-alpha(
          constructor: constructor, self.page-args.fill, alpha), body)
      }
      self
    },
    // dynamic control
    uncover: utils.uncover,
    only: utils.only,
    alternatives-match: utils.alternatives-match,
    alternatives: utils.alternatives,
    alternatives-fn: utils.alternatives-fn,
    alternatives-cases: utils.alternatives-cases,
    // alert interface
    alert: utils.wrap-method(text.with(weight: "bold")),
    // handout mode
    enable-handout-mode: (self: utils.empty-object) => {
      self.handout = true
      self
    },
    // disable pdfpc-file mode
    disable-pdfpc-file: (self: utils.empty-object) => {
      self.pdfpc-file = false
      self
    },
    // default slide
    touying-slide: touying-slide,
    slide: touying-slide,
    // append the preamble
    append-preamble: (self: utils.empty-object, preamble) => {
      self.preamble += preamble
      self
    },
    // datetime format
    datetime-format: (self: utils.empty-object, format) => {
      self.datetime-format = format
      self
    },
    // default init
    init: (self: utils.empty-object, body) => {
      // default text size
      set text(size: 20pt)
      body
    },
    // default outline
    touying-outline: (self: utils.empty-object, ..args) => {
      states.touying-outline(..args)
    },
    appendix: (self: utils.empty-object) => {
      self.appendix = true
      self
    }
  ),
)