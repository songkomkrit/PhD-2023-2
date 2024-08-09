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
int mdimold = 4;	// dimension			// 4 or 184 or 8
int mdimcontold = 2; // continuous dimension	// 2 or 66 or 3
//int mdimcat = 2; // categorical dimension	// 2 or 118 or 5
int mN = 8;	// number of instances	// 8 or 157681 or 100
int mn = 1;		// the value of n = (number of classes) - 1		// 1 or 4 or 4

int mseltol = 2;	// given number of total selected cont/cat dimensions (at most)

// Initialized UB on number of selected continuous dimensions
int mselcont = mdimcontold;
execute {
	if (mselcont > mseltol)
		mselcont = mseltol;
}

int mexccont = mdimcontold - mselcont;	// computed LB on number of excluded continuous dimensions
int mdim = mdimold - mexccont;
int mdimcont = mselcont;

range mDS = 1..mdim;
range mDSCONTOLD = 1..mdimcontold;	// old continuous
range mDSCONT = 1..mselcont;	// new continuous
range mDSCAT = mdimcont+1..mdim;	// shifted categorical
range mIS = 1..mN;
float mxcontold[mIS][mDSCONTOLD];	// x along continuous dimensions
int mxcat[mIS][mDSCAT]; // x along categorical dimensions
int my[mIS];
int mmaxlab[mDSCAT];	// maximum labels for categorical dimensions
float mM[mDS];	// big-M for all new/shifted dimensions (continuous and categorical)
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
	var pcont0 = 2;			// max number of cuts along continuous axis (integer)
	
	// Cplex limit parameters
	var tlimin = 5;			// cplex time limit (in minutes)
	var tlim = 60*tlimin;		// cplex time limit (in seconds)
	
	// Postfixes
	var cpostfixname = "mseltol-" + thisOplModel.mseltol + "-";
	cpostfixname += "t-" + tlimin + ".csv";	// common postfix name
	var postfixerror = "-" + cpostfixname;	// postfix of error file
	var postfixout = "-pcont-" + pcont0 + "-" + cpostfixname;	// postfix of all other output filess
	
	// Outputs
	var outerror = new IloOplOutputFile(prefixout + "export-error" + postfixerror, true); // append = true
	var outinstance = new IloOplOutputFile(prefixout + "export-predict-instance" + postfixout);
	var outcutcont = new IloOplOutputFile(prefixout + "export-cutcont-full" + postfixout);
	var outcutcat = new IloOplOutputFile(prefixout + "export-cutcat-full" + postfixout);
	// The existence of region is not checked here
	// In fact, it can be check through enumeration of certain binary representations
	var outregion = new IloOplOutputFile(prefixout + "export-predict-region" + postfixout);
	var outselvarint = new IloOplOutputFile(prefixout + "export-select-var-int" + postfixout); // selected variables (integer)
	var outselvarstr = new IloOplOutputFile(prefixout + "export-select-var-str" + postfixout); // selected variables (string)
	
	// OPL
	var source = new IloOplModelSource("p-mixed-cuts-seltol.mod");
	var cplex = new IloCplex();
	var def = new IloOplModelDefinition(source);
	var opl = new IloOplModel(def,cplex);
	var data = new IloOplDataElements();
	
	data.dimold = thisOplModel.mdimold;
	data.dimcontold = thisOplModel.mdimcontold;
	data.dim = thisOplModel.mdim;
	data.dimcont = thisOplModel.mdimcont;
	//data.dimcat = thisOplModel.mdimcat;
	data.N = thisOplModel.mN;
	data.n = thisOplModel.mn;
	data.xcontold = thisOplModel.mxcontold;
	data.xcat = thisOplModel.mxcat;
	data.y = thisOplModel.my;
	
	data.seltol = thisOplModel.mseltol;
	data.selcont = thisOplModel.mselcont;
	data.exccont = thisOplModel.mexccont;
	
	data.m = thisOplModel.mm;
	for (var j=1; j<=data.dimcont; j++)
		data.m[j] = m0;
	
	var f = new IloOplInputFile(infilename);		// training dataset
	for (var i=1; i<=data.N; i++) {
		var myitem = f.readline().split(",");
		data.y[i] = Opl.intValue(myitem[data.dimold]);
		for (var j=1; j<=data.dimcontold; j++)
			data.xcontold[i][j] = Opl.floatValue(myitem[j-1]);
		for (var j=data.dimcontold+1; j<=data.dimold; j++)
			data.xcat[i][j-data.exccont] = Opl.intValue(myitem[j-1]);
	}
	f.close();

	data.p = thisOplModel.mp;
	for (var j=1; j<=data.dimcont; j++)
		data.p[j] = pcont0;
	
	data.M = thisOplModel.mM;
	data.maxlab = thisOplModel.mmaxlab;
	var M0cont = 1;
	var f = new IloOplInputFile(varfilename);		// variable info
	for (var j=1; j<=data.dimold; j++) {
		var myitem = f.readline().split(",");
		if (j <= data.dimcontold) {
			var curMcont = 1 + Opl.maxl(Opl.abs(Opl.intValue(myitem[3])), Opl.abs(Opl.intValue(myitem[4])));
			M0cont = Opl.maxl(M0cont, curMcont);
		}		
		else {
			data.p[j-data.exccont] = Opl.intValue(myitem[5]);
			data.maxlab[j-data.exccont] = Opl.intValue(myitem[4]);
			data.M[j-data.exccont] = 1 + Opl.intValue(myitem[5]);
 		}			
	}
	f.close();
	
	for (var j=1; j<=data.dimcont; j++)
		data.M[j] = M0cont;
	
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

		// Scripting logs 1
		writeln("\n------------------------------");
		writeln("Bounds on # of cuts = ", nump, " with", data.p);
		writeln("Error = ", error, " (out of ", data.N, " instances)");
		writeln("Accuracy = ", accuracy);
		writeln("Solving time = ", solvetime, " ms (milliseconds)");
		writeln("Selected variables:");
		
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
		
		// outselvarint
		outselvarint.write("j,jold,mselect,type")	// mselect = model select (not actual)
		for (var j=1; j<=data.dimcont; j++) {	// selected continuous features
			outselvarint.write("\n", j, ",");
			var seljold = -1;
			for (var jold=1; jold<=data.dimcontold; jold++)
				// Determine which old continuous feature is selected
				if (opl.ccont.solutionValue[j][jold] == 1) {
					seljold = jold;
					break;	// terminate the loop
				}
			outselvarint.write(seljold, ",");
			outselvarint.write("1,");	// Based on model, all new cont features are selected
			outselvarint.write("cont");	
		}
		for (var j=data.dimcont+1; j<=data.dim; j++) {	// categorical feature
			outselvarint.write("\n", j, ",", j+data.exccont, ",");
			if (opl.f.solutionValue[j] == 1)	// selected categorical feature (model)
				outselvarint.write("1,");
			else	// unselected categorical feature (model)
				outselvarint.write("0,");
			outselvarint.write("cat");	
		}
		outselvarint.close();
		
		// outselvarstr
		outselvarstr.write("jold,jnew,aselect,type,variable"); // aselect = actual select
		var varinfile = new IloOplInputFile(varfilename);		// variable info
		var numselcont = 0;	// initialized number of actually selected continuous features
		var numselcat = 0;	// initialized number of actually selected categorical features
		for (var jold=1; jold<=data.dimcontold; jold++) {	// CONTINUOUS
		 	outselvarstr.write("\n", jold, ",");
		 	var jnew = -1;
		 	var aselect = 0;	// initialized to be unselected (continuous)
		 	for (var j=1; j<=data.dimcont; j++)
		 		// Determine whether a current old continuous feature is selected
		 		if (opl.ccont.solutionValue[j][jold] == 1) {	// selected (actual 1/2)
		 			jnew = j;
		 			break;	// terminate the loop
		 		}
		 	outselvarstr.write(jnew, ",");
		 	var myitem = varinfile.readline().split(",");
		 	if (jnew > 0) {	// selected continuous feature (actual 1/2)
		 		aselect = 1;	// seem to be selected (initialization for actual 2/2)
		 		for (var q=0; q<=data.p[jnew]; q++) {
		 			var bcleft = opl.bc.solutionValue[thisOplModel.mContPairs.find(jnew,q)];
		 			var bcright = opl.bc.solutionValue[thisOplModel.mContPairs.find(jnew,q+1)];
		 			if ((bcleft <= myitem[3]) && (bcright >= myitem[4])) {	// cover [min,max]
		 				aselect = 0;	// unselected (actual 2/2)
		 				break;
		 			}
		 		}
  			}		 	
		 	outselvarstr.write(aselect, ",");
		 	if (aselect == 1) { // actually selected continuous feature
		 		// Scripting logs 2 (continuous)
		 		write("\t", myitem[1], " (Continuous)\n");
		 		numselcont += 1;	 	  
		 	}
		 	outselvarstr.write("cont,");
		 	outselvarstr.write(myitem[1]);	// variable name
		}
		for (var jold=data.dimcontold+1; jold<=data.dimold; jold++) {	// CATEGORICAL
			var jnew = jold-data.exccont;
			outselvarstr.write("\n", jold, ",", jnew, ",");
			var aselect = 0;	// initialized to be unselected (categorical)
			var myitem = varinfile.readline().split(",");
			if (opl.f.solutionValue[jnew] == 1) {	// selected categorical feature (actual 1/2)
 				var vat0 = opl.v.solutionValue[thisOplModel.mCatPairs.find(jnew,0)];
 				for (var l=1; l<=data.maxlab[jnew]; l++) {
 					var vcur = opl.v.solutionValue[thisOplModel.mCatPairs.find(jnew,l)];
 					if (vcur != vat0) {	// distinct new groups are detected
 						aselect = 1;	// selected categorical feature (actual 2/2)
 						break;
 					}
 				}
 			}
 			outselvarstr.write(aselect, ",");
 			if (aselect == 1) {	// actually selected categorical feature
				// Scripting logs 2 (categorical)
				write("\t", myitem[1], " (Categorical)\n");
				numselcat += 1;				
 			}
			outselvarstr.write("cat,");	
		 	outselvarstr.write(myitem[1]);
		}
		varinfile.close();
		outselvarstr.close();
		
		// Scripting logs 3
		var numselall = numselcont + numselcat;
		writeln("Number of selected variables = ", numselall, " (", numselcont, " continuous + ", numselcat, " categorical)");
		writeln("------------------------------");
	}
	else
		writeln("No solution");
		
	opl.end();
	data.end(); 
	def.end(); 
	cplex.end(); 
	source.end();	
}