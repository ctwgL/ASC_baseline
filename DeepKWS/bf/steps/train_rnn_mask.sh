#!/bin/bash
# wujian@2018

set -ue

. ./path.sh || exit 1

train_dir=data/mask_train_simu
online_ivector_dir=

train_stage=-6
train_cmd="run.pl"

initial_effective_lrate=0.0001
final_effective_lrate=0.00005
num_epochs=40
num_jobs_initial=1
num_jobs_final=1
remove_egs=true
use_gpu=true

minibatch=128
momentum=0.8
input_model=

# samples_per_iter=80000

stage=2
egs_nj=16
egs_dev_subset=500
cmvn_opts="--norm-vars=true --norm-means=true"
# default 400000
samples_per_iter=50000
preserve_model_interval=5

# chunk_width=140,100,160
chunk_width=64,80,100
chunk_left_context=20
chunk_right_context=20

nj=20
stft_dim=513

label_delay=0
nonlinear=sigmoid 

mdl=lstm
exp_dir=exp/mask/tune

. parse_options.sh || exit 1

egs_opts="--nj $egs_nj --num-utts-subset $egs_dev_subset"

# it's a RNN model
if [ $stage -eq 1 ]; then

  mkdir -p $exp_dir/configs
  input_dim=$(feat-to-dim scp:$train_dir/feats.scp -)

  case $mdl in
    blstmp )
    echo "$0: config fast-bi-lstmp-batchnorm networks..."
    opts="dropout-proportion=0.2 decay-time=20 l2-regularize=0.0"

    cat <<EOF > $exp_dir/configs/network.xconfig
# input dim=100 name=ivector
input dim=$input_dim name=input
fast-lstmp-batchnorm-layer name=f-blstm1 cell-dim=512 recurrent-projection-dim=256 non-recurrent-projection-dim=256 delay=-3 $opts 
fast-lstmp-batchnorm-layer name=b-blstm1 cell-dim=512 recurrent-projection-dim=256 non-recurrent-projection-dim=256 delay=3 $opts 
fast-lstmp-batchnorm-layer name=f-blstm2 input=Append(f-blstm1, b-blstm1) cell-dim=512 recurrent-projection-dim=256 non-recurrent-projection-dim=256 delay=-3 $opts 
fast-lstmp-batchnorm-layer name=b-blstm2 input=Append(f-blstm1, b-blstm1) cell-dim=512 recurrent-projection-dim=256 non-recurrent-projection-dim=256 delay=3 $opts 
fast-lstmp-batchnorm-layer name=f-blstm3 input=Append(f-blstm2, b-blstm2) cell-dim=512 recurrent-projection-dim=256 non-recurrent-projection-dim=256 delay=-3 $opts 
fast-lstmp-batchnorm-layer name=b-blstm3 input=Append(f-blstm2, b-blstm2) cell-dim=512 recurrent-projection-dim=256 non-recurrent-projection-dim=256 delay=3 $opts 
output-layer name=output input=Append(f-blstm3, b-blstm3) output-delay=0 dim=513 include-activation=$nonlinear include-log-softmax=false objective-type=quadratic 
EOF
      ;;
    tdnn_blstmp )
    echo "$0: config tdnn && fast-bi-lstmp-batchnorm networks..."
    lstm_opts="dropout-proportion=0.2 decay-time=20 l2-regularize=0.0"
    tdnn_opts="l2-regularize=0.01"
    cat <<EOF > $exp_dir/configs/network.xconfig
input dim=$input_dim name=input
relu-batchnorm-layer name=tdnn1 $tdnn_opts dim=512 input=Append(-2,-1,0,1,2)
relu-batchnorm-layer name=tdnn2 $tdnn_opts dim=512 input=Append(-1,0,1)
fast-lstmp-batchnorm-layer name=f-blstm1 cell-dim=512 recurrent-projection-dim=256 non-recurrent-projection-dim=256 delay=-3 $lstm_opts
fast-lstmp-batchnorm-layer name=b-blstm1 cell-dim=512 recurrent-projection-dim=256 non-recurrent-projection-dim=256 delay=3 $lstm_opts
fast-lstmp-batchnorm-layer name=f-blstm2 input=Append(f-blstm1, b-blstm1) cell-dim=512 recurrent-projection-dim=256 non-recurrent-projection-dim=256 delay=-3 $lstm_opts
fast-lstmp-batchnorm-layer name=b-blstm2 input=Append(f-blstm1, b-blstm1) cell-dim=512 recurrent-projection-dim=256 non-recurrent-projection-dim=256 delay=3 $lstm_opts
fast-lstmp-batchnorm-layer name=f-blstm3 input=Append(f-blstm2, b-blstm2) cell-dim=512 recurrent-projection-dim=256 non-recurrent-projection-dim=256 delay=-3 $lstm_opts
fast-lstmp-batchnorm-layer name=b-blstm3 input=Append(f-blstm2, b-blstm2) cell-dim=512 recurrent-projection-dim=256 non-recurrent-projection-dim=256 delay=3 $lstm_opts
output-layer name=output input=Append(f-blstm3, b-blstm3) output-delay=0 dim=513 include-activation=$nonlinear include-log-softmax=false objective-type=quadratic 
EOF
      ;;
    cnn_blstmp )
    lstm_opts="dropout-proportion=0.2 decay-time=20 l2-regularize=0.0001"
    cnn_opts="l2-regularize=0.001"
    cat <<EOF > $exp_dir/configs/network.xconfig
input dim=$input_dim name=input

conv-relu-batchnorm-layer name=cnn1 height-in=$input_dim height-out=40 time-offsets=-1,0,1 height-offsets=-1,0,1 num-filters-out=32 $cnn_opts
conv-relu-batchnorm-layer name=cnn2 height-in=40 height-out=40 time-offsets=-1,0,1 height-offsets=-1,0,1 num-filters-out=32 $cnn_opts
conv-relu-batchnorm-layer name=cnn3 height-in=40 height-out=20 height-subsample-out=2 time-offsets=-1,0,1 height-offsets=-1,0,1 num-filters-out=128 $cnn_opts
conv-relu-batchnorm-layer name=cnn4 height-in=20 height-out=20 time-offsets=-1,0,1 height-offsets=-1,0,1 num-filters-out=64 $cnn_opts
conv-relu-batchnorm-layer name=cnn5 height-in=20 height-out=20 time-offsets=-3,0,3 height-offsets=-1,0,1 num-filters-out=32 $cnn_opts

fast-lstmp-batchnorm-layer name=f-blstm1 cell-dim=512 recurrent-projection-dim=256 non-recurrent-projection-dim=256 delay=-3 $lstm_opts
fast-lstmp-batchnorm-layer name=b-blstm1 cell-dim=512 recurrent-projection-dim=256 non-recurrent-projection-dim=256 delay=3 $lstm_opts
fast-lstmp-batchnorm-layer name=f-blstm2 input=Append(f-blstm1, b-blstm1) cell-dim=512 recurrent-projection-dim=256 non-recurrent-projection-dim=256 delay=-3 $lstm_opts
fast-lstmp-batchnorm-layer name=b-blstm2 input=Append(f-blstm1, b-blstm1) cell-dim=512 recurrent-projection-dim=256 non-recurrent-projection-dim=256 delay=3 $lstm_opts
output-layer name=output input=Append(f-blstm2, b-blstm2) output-delay=0 dim=513 include-activation=$nonlinear include-log-softmax=false objective-type=quadratic 
EOF
      ;;
    lstm )
      echo "$0: config fast-lstm-batchnorm networks..."
      cat <<EOF > $exp_dir/configs/network.xconfig
input dim=$input_dim name=input
fast-lstm-batchnorm-layer name=lstm1 cell-dim=512 
fast-lstm-batchnorm-layer name=lstm2 cell-dim=512 
fast-lstm-batchnorm-layer name=lstm3 cell-dim=512 
fast-lstm-batchnorm-layer name=lstm4 cell-dim=512 
output-layer name=output input=lstm4 output-delay=$label_delay dim=$stft_dim include-activation=$nonlinear include-log-softmax=false objective-type=quadratic
EOF
      ;;
    lstmp )
      echo "$0: config fast-uni-lstmp-batchnorm networks..."
      cat <<EOF > $exp_dir/configs/network.xconfig
input dim=$input_dim name=input
fast-lstmp-batchnorm-layer name=lstm1 cell-dim=1024 recurrent-projection-dim=256 non-recurrent-projection-dim=256
fast-lstmp-batchnorm-layer name=lstm2 cell-dim=1024 recurrent-projection-dim=256 non-recurrent-projection-dim=256
fast-lstmp-batchnorm-layer name=lstm3 cell-dim=1024 recurrent-projection-dim=256 non-recurrent-projection-dim=256
fast-lstmp-batchnorm-layer name=lstm4 cell-dim=1024 recurrent-projection-dim=256 non-recurrent-projection-dim=256
output-layer name=output input=lstm4 output-delay=$label_delay dim=$stft_dim include-activation=$nonlinear include-log-softmax=false objective-type=quadratic
EOF
      ;;
    *)
      echo "Unknown model type $mdl"
      exit 1
      ;;
  esac
  steps/nnet3/xconfig_to_configs.py --xconfig-file $exp_dir/configs/network.xconfig --config-dir $exp_dir/configs/
fi

if [ $stage -eq 2 ]; then
    echo "$0: training mask prediction networks..."
    steps/nnet3/train_raw_rnn.py --stage=$train_stage \
        --cmd=$train_cmd \
        --feat.cmvn-opts="$cmvn_opts" \
        --feat.online-ivector-dir "$online_ivector_dir" \
        --trainer.num-epochs $num_epochs \
        --trainer.optimization.num-jobs-initial $num_jobs_initial \
        --trainer.optimization.num-jobs-final $num_jobs_final \
        --trainer.optimization.initial-effective-lrate $initial_effective_lrate \
        --trainer.optimization.final-effective-lrate $final_effective_lrate \
        --trainer.rnn.num-chunk-per-minibatch $minibatch \
        --trainer.optimization.do-final-combination false \
        --trainer.optimization.momentum $momentum \
        --trainer.samples-per-iter $samples_per_iter \
        --trainer.input-model "$input_model" \
        --cleanup.remove-egs $remove_egs \
        --cleanup.preserve-model-interval $preserve_model_interval \
        --targets-scp $train_dir/mask.scp \
        --egs.chunk-width $chunk_width \
        --egs.chunk-left-context $chunk_left_context \
        --egs.chunk-right-context $chunk_right_context \
        --feat-dir $train_dir \
        --use-gpu $use_gpu \
        --egs.opts "$egs_opts" \
        --nj $nj \
        --dir $exp_dir >> $exp_dir/train_rnn.log 2>&1 || exit 1;
fi

echo "$0: Done"
