#!/usr/bin/env bash

# wujian@2018

set -eu

nj=40
cmd="run.pl"
stft_conf=conf/stft.conf
mask_format="kaldi"
beamformer="mvdr"
# do ban or not
ban=false
post_masking=false
vad_proportion=1
# online
alpha=0.8
chunk_size=-1
channels=4
pmwf_ref=-1
pmwf_rank1_appro="none"
itf_mask=""

echo "$0 $@"

function usage {
  echo "Options:"
  echo "  --nj          <nj>                  # number of jobs to run parallel, (default=$nj)"
  echo "  --cmd         <run.pl|queue.pl>     # how to run jobs, (default=$cmd)"
  echo "  --stft-conf   <stft-conf>           # stft configurations files, (default=$stft_conf)"
  echo "  --mask-format <kaldi|numpy>         # load masks from np.ndarray instead, (default=$mask_format)"
  echo "  --itf-mask    <itf-mask>            # scripts of interfering masks, (default=$itf_mask)"
  echo "  --beamformer  <mvdr|pmwf-0|pmwf-1|gevd>    # type of adaptive beamformer to apply, (default=$beamformer)"
  echo "  --ban         <true|false>          # do ban or not, (default=$ban)"
  echo "  --pmwf-rank1-appro <eig|gev|none>   # weather to use rank1 approximation in PMWF, (default=$pmwf_rank1_appro)"
  echo "  --post-masking     <true|false>     # do TF-masking after beamforming or not, (default=$post_masking)"
  echo "  --vad-proportion   <proportion>     # vad proportion to filter silence masks, (default=$vad_proportion)"
  echo "  --alpha       <alpha>               # remember coefficient used in online version, (default=$alpha)"
  echo "  --chunk-size  <chunk-size>          # chunk size in online beamformer, (default=$chunk_size)"
  echo "  --channels    <channels>            # number of channels, (default=$channels)"
}

. ./path.sh
. ./utils/parse_options.sh || exit 1

[ $# -ne 3 ] && echo "Script format error: $0 <wav-scp> <mask-dir/mask-scp> <enhan-dir>" && usage && exit 1

wav_scp=$1
enhan_dir=$3

for x in $wav_scp $stft_conf; do [ ! -f $x ] && echo "$0: missing file: $x" && exit 1; done

dirname=$(basename $enhan_dir)
exp_dir=./exp/run_$beamformer/$dirname && mkdir -p $exp_dir

# if second parameter is a directory
if [ -d $2 ]; then
  [ $mask_format != "numpy" ] && echo "$0: $2 is a directory, expected to set --mask-format numpy" && exit 1
  find $2 -name "*.npy" | awk -F '/' '{printf("%s\t%s\n", $NF, $0)}' | \
    sed 's:\.npy::' | sort -k1 > $exp_dir/masks.scp
  echo "$0: Got $(cat $exp_dir/masks.scp | wc -l) numpy's masks"
else
  cp $2 $exp_dir/masks.scp
fi

awk '{print $1}' $exp_dir/masks.scp | ./utils/filter_scp.pl -f 1 - $wav_scp | sort -k1 > $exp_dir/wav.scp
echo "$0: Reduce $(cat $wav_scp | wc -l) utterances to $(cat $exp_dir/wav.scp | wc -l)"

wav_split_scp="" && for n in $(seq $nj); do wav_split_scp="$wav_split_scp $exp_dir/wav.$n.scp"; done
./utils/split_scp.pl $exp_dir/wav.scp $wav_split_scp

beamformer_opts=$(cat $stft_conf | xargs)
[ ! -z $itf_mask ] && beamformer_opts="$beamformer_opts --itf-mask $itf_mask"

if [ $chunk_size -gt 0 ]; then
  beamformer_opts="$beamformer_opts --online.alpha $alpha --online.chunk-size $chunk_size --online.channels $channels"
fi

mkdir -p $enhan_dir
$cmd JOB=1:$nj $exp_dir/log/run_$beamformer.JOB.log \
  ./scripts/sptk/apply_adaptive_beamformer.py \
  $beamformer_opts \
  --beamformer $beamformer \
  --mask-format $mask_format \
  --pmwf-ref $pmwf_ref \
  --ban $ban \
  --rank1-appro $pmwf_rank1_appro \
  --vad-proportion $vad_proportion \
  --post-masking $post_masking \
  $exp_dir/wav.JOB.scp \
  $exp_dir/masks.scp \
  $enhan_dir

echo "$0: Run $beamformer done!"

