#!/bin/bash
#SBATCH --job-name=test
#SBATCH --cpus-per-task=32
#SBATCH --mem-per-cpu=7GB
#SBATCH --nodes=2
#SBAT --tasks-per-node 1

## !!! Adjust the CPUS_PER_TASK variable below manually !!!
echo "*** Allocating $SLURM_MEM_PER_CPU  Mb per cpu"
echo "*** SLURM_JOB_NUM_NODES $SLURM_JOB_NUM_NODES"
echo "*** SLURM_JOB_CPUS_PER_NODE $SLURM_JOB_CPUS_PER_NODE" ## not an integer grrrr...
echo "*** SLURM_JOB_CPUS_PER_TASK $SLURM_JOB_CPUS_PER_TASK" ## empty although given grr...
CPUS_PER_TASK=32
MEM_PER_WORKER=$(($CPUS_PER_TASK * $SLURM_MEM_PER_CPU * 1024 * 1024))
echo "*** MEM_PER_WORKER $MEM_PER_WORKER"
CPUS_TOT=$(($SLURM_JOB_NUM_NODES * $CPUS_PER_TASK))
##worker_num=4 # Must be one less that the total number of nodes
worker_num=$(($SLURM_JOB_NUM_NODES-1))

module load system/Python-3.7.4
source /save/servin/Envs/yapp/bin/activate

nodes=$(scontrol show hostnames $SLURM_JOB_NODELIST) # Getting the node names
nodes_array=( $nodes )

node1=${nodes_array[0]}

ip_prefix=$(srun --nodes=1 --ntasks=1 -w $node1 hostname --ip-address) # Making address
suffix=':6379'
ip_head=$ip_prefix$suffix
redis_password=$(uuidgen)

export ip_head # Exporting for latter access by trainer.py


echo "Starting head node"
srun --nodes=1 --ntasks=1 -w $node1 ray start --block --head --redis-port=6379 --redis-password=$redis_password --num-cpus=$CPUS_PER_TASK --memory=$MEM_PER_WORKER& # Starting the head
sleep 30
# Make sure the head successfully starts before any worker does, otherwise
# the worker will not be able to connect to redis. In case of longer delay,
# adjust the sleeptime above to ensure proper order.

for ((  i=1; i<=$worker_num; i++ ))
do
  node2=${nodes_array[$i]}
  echo "Starting $node2"
  srun --nodes=1 --ntasks=1 -w $node2 ray start --block --address=$ip_head --redis-password=$redis_password --num-cpus=$CPUS_PER_TASK --memory=$MEM_PER_WORKER& # Starting the workers
  # Flag --block will keep ray process alive on each compute node.
  sleep 30
done

python -u trainer.py $redis_password $CPUS_TOT # Pass the total number of allocated CPUs
