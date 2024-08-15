# PhD-2023-2
PhD Dissertation Progress 2023/2

## Instructions
* Run Jupyter notebooks
  * datasets/jupyter/convert.ipynb (process/convert/encode data values)
  * datasets/jupyter/select.ipynb (select 100 samples with 8 mixed features)
  * setcut/jupyter/setcut.ipynb (set 2 cuts at maximum)
* Copy the following files to a reference location
  * metadata/full/meta-indep-cont-20.json
  * metadata/new/meta-indep-cat-20-enc.json
  * select/features/feature20num8.csv
  * select/features/score20num8.csv
  * select/traineach20/seltrain20num8each20.csv (with header)
  * select/traineach20/seltrain20num8each20noh.csv (without header)
  * select/cuts/selproc20num8co2ca2cutinfo.csv (with header)
  * select/cuts/selproc20num8co2ca2cutinfonoh.csv (without header)
* Copy the following files to an input directory of a CPLEX project
  * select/traineach20/seltrain20num8each20noh.csv
  * select/cuts/selproc20num8co2ca2cutinfonoh.csv
* Execute OPL projects (box classifiers)
  * ```cd box-classifiers```
  * ```cd mixed-boxes-full-seltol-limit``` or ```cd mixed-boxes-full-seltol-ws-limit```
  * ```oplrun -p .```
    * In this project, 5-minute limit is set throught the command ```cplex.tilim = 60*5```, for example
  * Results are exported in the output directory in CSV format
