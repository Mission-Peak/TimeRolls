"""Paintings people recognise, and that are out of copyright.

Two filters decided this list, and the second is unusual for us.

**Recognition, not merit.** The game asks "which one shows the Mona Lisa?", which only
works if somebody has seen it before. An art historian's hundred greatest paintings is a
different list from a hundred paintings an eighty-year-old will recognise across a room.

**Out of copyright, which rules out most of the twentieth century.** A faithful photograph
of a flat public-domain painting is itself public domain, which is what makes this pack
possible at all — but the *painting* has to be public domain first. That excludes Picasso,
Dalí, Matisse, O'Keeffe, Warhol, Hopper, Kahlo and Magritte, all of whom would otherwise
be obvious entries. Anything by an artist who died within the last seventy years is left
out, however famous.

Each entry: (slug, the name a player would use, what Commons files it under, artist, year).
"""

ARTWORKS = [
    # Renaissance and before
    ("mona-lisa", "The Mona Lisa", "Mona Lisa", "Leonardo da Vinci", 1503),
    ("last-supper", "The Last Supper", "Leonardo da Vinci Last Supper", "Leonardo da Vinci", 1498),
    ("creation-of-adam", "The Creation of Adam", "Michelangelo Creation of Adam", "Michelangelo", 1512),
    ("birth-of-venus", "The Birth of Venus", "Botticelli Birth of Venus", "Sandro Botticelli", 1486),
    ("primavera", "Primavera", "Botticelli Primavera", "Sandro Botticelli", 1480),
    ("school-of-athens", "The School of Athens", "Raphael School of Athens", "Raphael", 1511),
    ("vitruvian-man", "Vitruvian Man", "Leonardo Vitruvian Man", "Leonardo da Vinci", 1490),
    ("arnolfini-portrait", "The Arnolfini Portrait", "Van Eyck Arnolfini Portrait", "Jan van Eyck", 1434),
    ("garden-earthly-delights", "The Garden of Earthly Delights",
     "Bosch Garden of Earthly Delights", "Hieronymus Bosch", 1503),
    ("tower-of-babel", "The Tower of Babel", "Bruegel Tower of Babel", "Pieter Bruegel the Elder", 1563),
    ("hunters-in-the-snow", "Hunters in the Snow", "Bruegel Hunters in the Snow",
     "Pieter Bruegel the Elder", 1565),
    ("the-ambassadors", "The Ambassadors", "Holbein The Ambassadors", "Hans Holbein the Younger", 1533),

    # Dutch Golden Age and Baroque
    ("girl-with-a-pearl-earring", "Girl with a Pearl Earring",
     "Vermeer Girl with a Pearl Earring", "Johannes Vermeer", 1665),
    ("the-milkmaid", "The Milkmaid", "Vermeer The Milkmaid", "Johannes Vermeer", 1658),
    ("night-watch", "The Night Watch", "Rembrandt Night Watch", "Rembrandt", 1642),
    ("anatomy-lesson", "The Anatomy Lesson", "Rembrandt Anatomy Lesson Dr Tulp", "Rembrandt", 1632),
    ("las-meninas", "Las Meninas", "Velazquez Las Meninas", "Diego Velázquez", 1656),
    ("calling-of-st-matthew", "The Calling of Saint Matthew",
     "Caravaggio Calling of Saint Matthew", "Caravaggio", 1600),
    ("judith-holofernes", "Judith Slaying Holofernes",
     "Artemisia Gentileschi Judith Slaying Holofernes", "Artemisia Gentileschi", 1620),

    # Eighteenth and nineteenth century
    ("the-swing", "The Swing", "Fragonard The Swing", "Jean-Honoré Fragonard", 1767),
    ("third-of-may", "The Third of May 1808", "Goya Third of May 1808", "Francisco Goya", 1814),
    ("saturn-devouring", "Saturn", "Goya Saturn Devouring His Son", "Francisco Goya", 1823),
    ("liberty-leading", "Liberty Leading the People",
     "Delacroix Liberty Leading the People", "Eugène Delacroix", 1830),
    ("raft-of-the-medusa", "The Raft of the Medusa", "Gericault Raft of the Medusa",
     "Théodore Géricault", 1819),
    ("the-hay-wain", "The Hay Wain", "Constable The Hay Wain", "John Constable", 1821),
    ("fighting-temeraire", "The Fighting Temeraire", "Turner Fighting Temeraire", "J. M. W. Turner", 1839),
    ("rain-steam-speed", "Rain, Steam and Speed", "Turner Rain Steam and Speed", "J. M. W. Turner", 1844),
    ("wanderer-sea-of-fog", "Wanderer above the Sea of Fog",
     "Caspar David Friedrich Wanderer above the Sea of Fog", "Caspar David Friedrich", 1818),
    ("great-wave", "The Great Wave off Kanagawa", "Hokusai Great Wave off Kanagawa", "Hokusai", 1831),
    ("the-gleaners", "The Gleaners", "Millet The Gleaners", "Jean-François Millet", 1857),
    ("the-angelus", "The Angelus", "Millet The Angelus", "Jean-François Millet", 1859),
    ("whistlers-mother", "Whistler's Mother", "Whistler Arrangement in Grey and Black",
     "James McNeill Whistler", 1871),
    ("washington-crossing", "Washington Crossing the Delaware",
     "Leutze Washington Crossing the Delaware", "Emanuel Leutze", 1851),
    ("ophelia", "Ophelia", "Millais Ophelia", "John Everett Millais", 1852),
    ("the-lady-of-shalott", "The Lady of Shalott", "Waterhouse The Lady of Shalott",
     "John William Waterhouse", 1888),
    ("isle-of-the-dead", "The Isle of the Dead", "Bocklin Isle of the Dead", "Arnold Böcklin", 1883),

    # Impressionism and after
    ("impression-sunrise", "Impression, Sunrise", "Monet Impression Sunrise", "Claude Monet", 1872),
    ("water-lilies", "Water Lilies", "Monet Water Lilies", "Claude Monet", 1906),
    ("rouen-cathedral", "Rouen Cathedral", "Monet Rouen Cathedral", "Claude Monet", 1894),
    ("luncheon-boating-party", "Luncheon of the Boating Party",
     "Renoir Luncheon of the Boating Party", "Pierre-Auguste Renoir", 1881),
    ("bal-du-moulin", "Dance at Le Moulin de la Galette",
     "Renoir Bal du moulin de la Galette", "Pierre-Auguste Renoir", 1876),
    ("the-ballet-class", "The Ballet Class", "Degas The Ballet Class", "Edgar Degas", 1874),
    ("absinthe-drinker", "L'Absinthe", "Degas L'Absinthe", "Edgar Degas", 1876),
    ("dejeuner-sur-lherbe", "Le Déjeuner sur l'herbe", "Manet Le Dejeuner sur l'herbe", "Édouard Manet", 1863),
    ("olympia", "Olympia", "Manet Olympia", "Édouard Manet", 1863),
    ("bar-folies-bergere", "A Bar at the Folies-Bergère",
     "Manet Bar at the Folies-Bergere", "Édouard Manet", 1882),
    ("sunday-la-grande-jatte", "A Sunday on La Grande Jatte",
     "Seurat Sunday Afternoon Island La Grande Jatte", "Georges Seurat", 1886),
    ("starry-night", "Starry Night", "Van Gogh Starry Night", "Vincent van Gogh", 1889),
    ("sunflowers", "Sunflowers", "Van Gogh Sunflowers", "Vincent van Gogh", 1888),
    ("bedroom-in-arles", "Bedroom in Arles", "Van Gogh Bedroom in Arles", "Vincent van Gogh", 1888),
    ("cafe-terrace-at-night", "Café Terrace at Night",
     "Van Gogh Cafe Terrace at Night", "Vincent van Gogh", 1888),
    ("van-gogh-self-portrait", "Van Gogh's Self-Portrait",
     "Van Gogh Self-Portrait 1889", "Vincent van Gogh", 1889),
    ("the-scream", "The Scream", "Edvard Munch The Scream", "Edvard Munch", 1893),
    ("card-players", "The Card Players", "Cezanne The Card Players", "Paul Cézanne", 1892),
    ("mont-sainte-victoire", "Mont Sainte-Victoire", "Cezanne Mont Sainte-Victoire", "Paul Cézanne", 1890),
    ("where-do-we-come-from", "Where Do We Come From?",
     "Gauguin Where Do We Come From What Are We", "Paul Gauguin", 1897),
    ("the-kiss-klimt", "The Kiss", "Gustav Klimt The Kiss", "Gustav Klimt", 1908),
    ("portrait-adele", "Portrait of Adele Bloch-Bauer",
     "Klimt Portrait of Adele Bloch-Bauer I", "Gustav Klimt", 1907),
    ("the-sleeping-gypsy", "The Sleeping Gypsy", "Rousseau The Sleeping Gypsy", "Henri Rousseau", 1897),
    ("the-dream-rousseau", "The Dream", "Henri Rousseau The Dream", "Henri Rousseau", 1910),
    ("american-gothic", "American Gothic", "Grant Wood American Gothic", "Grant Wood", 1930),
]
