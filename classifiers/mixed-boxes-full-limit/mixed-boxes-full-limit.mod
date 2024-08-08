/*********************************************
 * OPL 22.1.1.0 Model
 * Author: songkomkrit
 * Creation Date: Jul 20, 2024 at 10:09:02 PM
 *********************************************/
 
/*********************************************
 * NOTES
 * pl.bc.solutionValue[thisOplModel.mPairs.find(1,0)]
 *********************************************/

/*********************************************
 * Class Labels
 * Input file: 0, 1, 2, ..., n
 * Algorithm: 0, 1, 2, ..., n
 * Output file: 0, 1, 2, ..., n
 *********************************************/

/*********************************************
 * INPUTS
 *********************************************/ 
int mdim = 8;	// dimension			// 3 or 184 or 8
int mdimcont = 3; // continuous dimension	// 2 or 66 or 3
//int mdimcat = 5; // categorical dimension	// 1 or 118 or 5
int mN = 100;	// number of instances	// 8 or 157681 or 100
int mn = 4;		// the value of n = (number of classes) - 1		// 1 or 4 or 4

range mDS = 1..mdim;
range mDSCONT = 1..mdimcont;
range mDSCAT = mdimcont+1..mdim;
range mIS = 1..mN;
float mxcont[mIS][mDSCONT];	// x along continuous dimensions
int mxcat[mIS][mDSCAT]; // x along categorical dimensions
int my[mIS];
int mmaxlab[mDSCAT];	// maximum labels for categorical dimensions
float mM[mDSCONT];	// big-M for continuous dimensions
float mm[mDSCONT];	// small-m for continuous dimensions
int mp[mDS];	// number of cuts along axes
int mcoef[mDS];

/*********************************************
 * TUPLES
 *********************************************/ 
tuple ContPairType {	// index for continuous cut
	int j;
	int q;
};

{ContPairType} mContPairs = {<j, q> | j in mDSCONT, q in 0..mp[j]+1};

tuple ContTripleType {	// index for continuous cut of each individual instance
	int i;
	int j;
	int q;
};

{ContTripleType} mContTriples = {<i, j, q> | i in mIS, j in mDSCONT, q in 0..mp[j]};

tuple CatPairType {	// index for categorical group
	int j;
	int l;
};

{CatPairType} mCatPairs = {<j, l> | j in mDSCAT, l in 0..mmaxlab[j]};

/*********************************************
 * MAIN EXECUTION
 *********************************************/ 
main {
	var curtime5 = Opl.round((new Date()).getTime()/1000) % 100000; // in seconds
	
	var infilename = "input/testin.csv";			// input filename
	var varfilename = "input/testvar.csv";			// variable filename (6 columns)
	var prefixout = "output/" + curtime5 + "-";		// prefix of all output files
	prefixout += infilename.split("/")[1].split(".")[0] + "-";

	// Inputs
	//var M0 = 500;			// big-M (float)
	var m0 = 0.01;			// small-m (float)
	//var p0 = 2;				// maximal number of cuts along each axis (integer) (not input)
	
	// Cplex limit parameters
	var tlim = 60*5;		// cplex time limit (in seconds)
	
	//var postfixerror = "-M-" + M0 + "-m-" + m0 + ".csv";	// postfix of error file
	var postfixerror = ".csv";
	//var postfixout = "-p-" + p0 + "-M-" + M0 + "-m-" + m0 + ".csv";	// postfix of all other output files
	var postfixout = ".csv"
	
	// Outputs
	var outerror = new IloOplOutputFile(prefixout + "export-error" + postfixerror, true); // append = true
	var outinstance = new IloOplOutputFile(prefixout + "export-predict-instance" + postfixout);
	var outcutcont = new IloOplOutputFile(prefixout + "export-cutcont-full" + postfixout);
	var outcutcat = new IloOplOutputFile(prefixout + "export-cutcat-full" + postfixout);
	var outregion = new IloOplOutputFile(prefixout + "export-predict-region" + postfixout);
	
	// OPL
	var source = new IloOplModelSource("p-mixed-cuts.mod");
	var cplex = new IloCplex();
	var def = new IloOplModelDefinition(source);
	var opl = new IloOplModel(def,cplex);
	var data = new IloOplDataElements();
	
	data.dim = thisOplModel.mdim;
	data.dimcont = thisOplModel.mdimcont;
	//data.dimcat = thisOplModel.mdimcat;
	data.N = thisOplModel.mN;
	data.n = thisOplModel.mn;
	data.xcont = thisOplModel.mxcont;
	data.xcat = thisOplModel.mxcat;
	data.y = thisOplModel.my;
	
	data.m = thisOplModel.mm;
	for (var j=1; j<=data.dimcont; j++)
		data.m[j] = m0;
	
	var f = new IloOplInputFile(infilename);		// training dataset
	for (var i=1; i<=data.N; i++) {
		var myitem = f.readline().split(",");
		data.y[i] = Opl.intValue(myitem[data.dim]);
		for (var j=1; j<=data.dimcont; j++)
			data.xcont[i][j] = Opl.floatValue(myitem[j-1]);
		for (var j=data.dimcont+1; j<=data.dim; j++)
			data.xcat[i][j] = Opl.intValue(myitem[j-1]);
	}
	f.close();
	
	data.p = thisOplModel.mp;
	data.M = thisOplModel.mM;
	data.maxlab = thisOplModel.mmaxlab;
	var f = new IloOplInputFile(varfilename);		// variable info
	for (var j=1; j<=data.dim; j++) {
		var myitem = f.readline().split(",");
		data.p[j] = Opl.intValue(myitem[5]);
		if (j <= data.dimcont)
			data.M[j] = 1 + Opl.maxl(Opl.abs(Opl.intValue(myitem[3])), Opl.abs(Opl.intValue(myitem[4])))
		else
			data.maxlab[j] = Opl.intValue(myitem[4]);		
	}
	f.close();
	
	data.coef = thisOplModel.mcoef;	
	data.coef[1] = 1;
	for (var j=2; j<=data.dim; j++)
		data.coef[j] = data.coef[j-1]*(data.p[j]+1);
	
	var nump = 0;		// total number of cuts
	for (var j=1; j<=data.dim; j++)
	nump += data.p[j];
	
	opl.addDataSource(data);
	opl.generate();
	opl.settings.mainEndEnabled = true;
	
	// Cplex limits
	cplex.tilim = tlim;			// in seconds
	
	var start = new Date();		// begin a timer
	
	if (cplex.solve()) {
	
		var end = new Date();	// end a timer
		var solvetime = end.getTime() - start.getTime();	// compute solving time
		
		var error = cplex.getObjValue();		// the number of misclassified instances
		var accuracy = (1-error/data.N)*100;	// training accuracy
		
		// outerror
		if (!outerror.exists) {
			for (var j=1; j<=data.dim; j++)	
				outerror.write("p", j, ",");
			outerror.write("error,accuracy,ms");
		}		
		outerror.write("\n");
		for (var j=1; j<=data.dim; j++)
			outerror.write(data.p[j], ",");		
		outerror.write(error, ",", accuracy, ",", solvetime);
		outerror.close();
		
		// Scripting logs
		writeln("Bounds on # of cuts = ", nump, " with", data.p);
		writeln("Error = ", error, " (out of ", data.N, " instances)");
		writeln("Accuracy = ", accuracy);
		writeln("Solving time = ", solvetime, " ms (milliseconds)");
		writeln("------------------------------");
		
		// outinstance
		outinstance.write("id,class,predict");
		for (var i=1; i<=data.N; i++) {
			outinstance.write("\n", i, ",", data.y[i], ",");
			for (var b=0; b<opl.B; b++) 
				if (opl.g.solutionValue[i][b] == 1) {	// occur only once
					outinstance.write(opl.theta.solutionValue[b]);	
					break;	// terminate the loop
				}		
		}
		outinstance.close();
		
		// outcutcont
		outcutcont.write("j,q,bc");
		for (var j=1; j<=data.dimcont; j++) {
			for (var q=1; q<=data.p[j]; q++) {
				outcutcont.write("\n", j, ",", q, ",");
				outcutcont.write(opl.bc.solutionValue[thisOplModel.mContPairs.find(j,q)]);		
			}
		}
		outcutcont.close();

		// outcutcat
		outcutcat.write("j,l,v");
		for (var j=data.dimcont+1; j<=data.dim; j++) {
			for (var l=0; l<=data.maxlab[j]; l++) {
				outcutcat.write("\n", j, ",", l, ",");
				outcutcat.write(opl.v.solutionValue[thisOplModel.mCatPairs.find(j,l)]);		
			}	
		}
		outcutcat.close();
		
		// outregion
		outregion.write("region,occupy,predict");
		for (var b=0; b<opl.B; b++) {
			outregion.write("\n", b, ",");
			var s = 0;		// initialize s (presumably unoccupied)
			for (var i=1; i<=data.N; i++)
				if (opl.g.solutionValue[i][b] == 1) {	// occupied
					s = 1;
					break;	// terminate the loop					
				}
			outregion.write(s, ",");
			outregion.write(opl.theta.solutionValue[b]);		
		}
		outregion.close();
	}
	else
		writeln("No solution");
		
	opl.end();
	data.end(); 
	def.end(); 
	cplex.end(); 
	source.end();	
}