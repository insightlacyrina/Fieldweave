FieldWeave portable FIR package

configuration.json can be re-opened in FieldWeave; imported WAV assets are bundled under assets/.
LL = left source -> left ear; LR = left source -> right ear;
RL = right source -> left ear; RR = right source -> right ear.
Each filter is mono IEEE Float32 WAV. FIR sample rate: 48000 Hz.
CamillaDSP YAML files are templates; run from this directory so relative asset paths resolve.
CoreAudio device names must be reviewed manually. Export does not install drivers or change routing.
Offline CamillaDSP template uses interleaved F64_LE raw files, not WAV.
response.csv contains linear magnitudes of the final four transfer paths.
