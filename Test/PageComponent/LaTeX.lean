import ProofScript


set_option pageBuild true

#page latex (title := "Functorial Morphism's Godement Product") r#"
  \begin{align*}
    \begin{tikzcd}[column sep=4em, ampersand replacement=\&]
      \mathscr A
        \arrow[r, bend left=50, "F"{yshift=0.1em}, ""{name=U1, below}]
        \arrow[r, bend right=50, "G"'{yshift=-0.1em}, ""{name=D1, above}]
        \arrow[Rightarrow, from=U1, to=D1, "\alpha"{xshift=0.1em}, shorten <=1pt, shorten >=1pt]
      \&
      \mathscr B
        \arrow[r, bend left=50, "F'"{yshift=0.1em}, ""{name=U2, below}]
        \arrow[r, bend right=50, "G'"'{yshift=-0.1em}, ""{name=D2, above}]
        \arrow[Rightarrow, from=U2, to=D2, "\alpha'"{xshift=0.1em}, shorten <=1pt, shorten >=1pt]
      \&
      \mathscr C
    \end{tikzcd}
    \longmapsto
    \begin{tikzcd}[column sep=5em, ampersand replacement=\&]
      \mathscr A
        \arrow[r, bend left=50, "F'\circ F"{yshift=0.1em}, ""{name=U1, below}]
        \arrow[r, bend right=50, "G'\circ G"'{yshift=-0.1em}, ""{name=D1, above}]
        \arrow[Rightarrow, from=U1, to=D1, "\alpha'\ast\alpha"{xshift=0.1em}, shorten <=1pt, shorten >=1pt]
      \&
      \mathscr C
    \end{tikzcd}
  \end{align*}
"#
