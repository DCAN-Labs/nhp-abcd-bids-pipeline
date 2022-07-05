# The DCAN Labs Macaque Pipeline

The dcan-macaque-pipeline was originally based on the Human Connectome Project's Minimal Preprocessing Pipeline, but grew into its own.  Base templates and surfaces are included from the Yerkes19, though you can input your own templates.

It is recommended to use the nhp-abcd-bids-pipeline BIDS App to run the pipeline, as there are many independent pieces which are stitched together in that BIDS App's Docker image on DockerHub.

The Examples/Scripts directory contains the basic individual building blocks of the pipeline (and some extra).  Running HCPPrep, PreFreeSurfer, FreeGrey, PostFreeSurfer, GenericfMRIVolume, GenericfMRISurface will complete the pipeline, but knowing the inputs to each script can be difficult to keep track of and will not be documented here.

Please cite these papers for use of this pipeline:

Autio, Joonas A, Glasser, Matthew F, Ose, Takayuki, Donahue, Chad J, Bastiani, Matteo, Ohno, Masahiro, Kawabata, Yoshihiko, Urushibata, Yuta, Murata, Katsutoshi, Nishigori, Kantaro, Yamaguchi, Masataka, Hori, Yuki, Yoshida, Atsushi, Go, Yasuhiro, Coalson, Timothy S, Jbabdi, Saad, Sotiropoulos, Stamatios N, Smith, Stephen, Van Essen, David C, Hayashi, Takuya. (2019). Towards HCP-Style Macaque Connectomes: 24-Channel 3T Multi-Array Coil, MRI Sequences and Preprocessing. BioRxiv, 602979. https://doi.org/10.1101/602979

Donahue, Chad J, Sotiropoulos, Stamatios N, Jbabdi, Saad, Hernandez-Fernandez, Moises, Behrens, Timothy E, Dyrby, Tim B, Coalson, Timothy, Kennedy, Henry, Knoblauch, Kenneth, Van Essen, David C, Glasser, Matthew F. (2016). Using Diffusion Tractography to Predict Cortical Connection Strength and Distance: A Quantitative Comparison with Tracers in the Monkey. The Journal of Neuroscience, 36(25), 6758 LP – 6770. https://doi.org/10.1523/JNEUROSCI.0493-16.2016

Glasser, Matthew F, Sotiropoulos, Stamatios N, Wilson, J Anthony, Coalson, Timothy S, Fischl, Bruce, Andersson, Jesper L, Xu, Junqian, Jbabdi, Saad, Webster, Matthew, Polimeni, Jonathan R, Van Essen, David C, Jenkinson, Mark. (2013). The minimal preprocessing pipelines for the Human Connectome Project. NeuroImage, 80, 105–124. https://doi.org/10.1016/j.neuroimage.2013.04.127
