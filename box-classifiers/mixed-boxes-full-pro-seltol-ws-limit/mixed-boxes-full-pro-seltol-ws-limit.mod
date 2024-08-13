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
int mdimold = 4;	// dimension			// 4 or 184 or 8 or 4
int mdimcontold = 2; // continuous dimension	// 2 or 66 or 3 or 2
//int mdimcat = 2; // categorical dimension	// 2 or 118 or 5 or 2
int mN = 100;	// number of instances	// 8 or 157681 or 100 or 100
int mn = 4;		// the value of n = (number of classes) - 1		// 1 or 4 or 4

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

// Given warm start
int mB = 192;	// number of decision regions
int msccont[mDSCONT][mDSCONTOLD];
int mse[mIS];
int msf[mDSCAT];
int mstheta[0..mB-1];
int msv[mDSCAT];
// Derived warm start
int msg[mIS][0..mB-1];
int msthetat[mIS][0..mB-1];

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
 * OUTSIDE EXECUTION
 *********************************************/
execute {
	thisOplModel.settings.run_engineLog = "tmp/current-engine.log";	// temporary engine log
}

/*********************************************
 * MAIN EXECUTION
 *********************************************/ 
main {
	var curtime5 = Opl.round((new Date()).getTime()/1000) % 100000; // in seconds
	
	var infilename = "input/seltrain20num4each20.csv";			// input filename
	var varfilename = "input/selproc20num4co3ca3cutinfo.csv";			// variable filename (6 columns)
	var prefixout = "output/" + curtime5 + "-";		// prefix of all output files
	prefixout += infilename.split("/")[1].split(".")[0] + "-";

	// Inputs
	//var M0 = 500;			// big-M (float)
	var m0 = 0.01;			// small-m (float)
	var pcont0 = 3;			// max number of cuts along continuous axis (integer)
	var timelimit = 1;		// whether set Cplex time limit (1 = limit / 0 = not limit)

	// Cplex limit parameters
	if (timelimit == 1) {
		var tlimin = 5;			// cplex time limit (in minutes)
		var tlim = 60*tlimin;	// cplex time limit (in seconds)
	}
	else
		var tlimin = 'na';
	
	// Warm start (Consider the case when no categorical feature is selected)
	var warmstart = 1;		// whether use a warm start (1 = use / 0 = not use)
	if (warmstart == 1) {
		var startdir = "start/num4";
		var insbcname = startdir + "/" + "sbc.csv";
		var insccontname = startdir + "/" + "sccont.csv";
		var insename = startdir + "/" + "se.csv";
		var insfname = startdir + "/" + "sf.csv";
		var insthetaname = startdir + "/" + "stheta.csv";
	}
	
	// Postfixes
	var cpostfixname = "mfullproseltol-" + thisOplModel.mseltol + "-ws-";
	cpostfixname += "t-" + tlimin + ".csv";	// common postfix name
	var postfixerror = "-" + cpostfixname;	// postfix of error file
	var postfixout = "-pcont-" + pcont0 + "-" + cpostfixname;	// postfix of all other output files
	
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

	// Engine log (initialized)
	var logfilename = "log/" + curtime5 + "-engine-" + cpostfixname.split(".")[0] + ".log";
	var outlog = new IloOplOutputFile(logfilename);
	
	// OPL (Warm start)
	if (warmstart == 1)
		var vectors= new IloOplCplexVectors();
	
	// OPL (Required)
	var source = new IloOplModelSource("p-mixed-cuts-pro-seltol.mod");
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
	
	var f = new IloOplInputFile(infilename);	// training dataset
	f.readline();								// skip a header
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
	var f = new IloOplInputFile(varfilename);	// variable info
	f.readline();								// skip a header
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
	
	// Finish up OPL settings
	opl.addDataSource(data);
	opl.generate();
	opl.settings.mainEndEnabled = true;
	
	// Cplex limits
	if (timelimit == 1)
		cplex.tilim = tlim;			// in seconds

	// Warm start preparation
	if (warmstart == 1) {
	  	// ccont (given)
		var insccont= new IloOplInputFile(insccontname);
		insccont.readline();	// skip a header
		for (var j=1; j<=data.dimcont; j++) {
			for (var jold=1; jold<=data.dimcontold; jold++) {
				var myitem = insccont.readline().split(",");
				thisOplModel.msccont[j][jold] = Opl.intValue(myitem[2]);
			}
		}
		insccont.close();
		vectors.attach(opl.ccont, thisOplModel.msccont);
		
		// e (given)
		var inse = new IloOplInputFile(insename);
		inse.readline();	// skip a header
		for (var i=1; i<=data.N; i++) {
			var myitem = inse.readline().split(",");
			thisOplModel.mse[i] = Opl.intValue(myitem[1]);
		}
		inse.close();
		vectors.attach(opl.e, thisOplModel.mse);
		
		// f (given)
		var insf = new IloOplInputFile(insfname);
		insf.readline();	// skip a header
		for (var j=data.dimcont+1; j<=data.dim; j++) {
			var myitem = insf.readline().split(",");
			thisOplModel.msf[j] = Opl.intValue(myitem[1]);
		}
		insf.close();
		vectors.attach(opl.f, thisOplModel.msf);
		
		// theta (given)
		var instheta = new IloOplInputFile(insthetaname);
		instheta.readline();	// skip a header
		for (var b=0; b<=thisOplModel.mB-1; b++) {
			var myitem = instheta.readline().split(",");
			thisOplModel.mstheta[b] = Opl.intValue(myitem[1]);		
		}
		instheta.close();
		vectors.attach(opl.theta, thisOplModel.mstheta);
		
		// g and thetat (derived) (It turns out to provide a slow search)
		/*
		for (var i=1; i<=data.N; i++) {
			// Only consider new continuous dimensions (by our initialization)
			var bcur = 0;	// initialize bcur first
			var insbc = new IloOplInputFile(insbcname);
			insbc.readline();	// skip a header
			for (var j=1; j<=data.dimcont; j++) {	// initialize only at cont
				for (var jold=1; jold<=data.dimcontold; jold++) {
					if (thisOplModel.msccont[j][jold] == 1) {
						var joldcur = jold;
						break;
					}
				}
				var qcur = data.p[j];	// initialize qcur first
				for (var q=1; q<=data.p[j]; q++) {
					var myitem = insbc.readline().split(",");
					if (data.xcontold[i][joldcur] <= Opl.floatValue(myitem[2])) {
						qcur = q-1;	// correct qcur (if possible)
						break;
					}
				}
				bcur += data.coef[j]*qcur;	// keep adjusting bcur
			}
			// Consider all decision boxes (continuous + categorical)
			for (var b=0; b<=thisOplModel.mB-1; b++) {
				thisOplModel.msg[i][b] = 0;
				thisOplModel.msthetat[i][b] = 0;
			}
			thisOplModel.msg[i][bcur] = 1;
			thisOplModel.msthetat[i][bcur] = thisOplModel.mstheta[bcur];
			insbc.close();
		}
		vectors.attach(opl.g, thisOplModel.msg);
		vectors.attach(opl.thetat, thisOplModel.msthetat);
		*/
		
		// Finalize
		vectors.setStart(cplex);
	}
	
	// Begin a timer
	var start = new Date();
	
	if (cplex.solve()) {
	
		var end = new Date();	// end a timer
		var solvetime = end.getTime() - start.getTime();	// compute solving time
		
		var error = cplex.getObjValue();		// the number of misclassified instances
		var accuracy = (1-error/data.N)*100;	// training accuracy

		var status = cplex.status;	// solution status code (1 = opt / 11 = time limit / ...)
		var lberr = cplex.getBestObjValue();	// LB on minimum (optimal) error
		var relgap = cplex.getMIPRelativeGap();	// relative objective gap for MIP
		
		// outerror
		if (!outerror.exists) {
			for (var j=1; j<=data.dim; j++)
				outerror.write("p", j, ",");
			outerror.write("error,accuracy,ms,status,lberr,relgap");
		}
		outerror.write("\n");
		for (var j=1; j<=data.dim; j++)
			outerror.write(data.p[j], ",");
		outerror.write(error, ",", accuracy, ",", solvetime, ",");
		outerror.write(status, ",", lberr, ",", relgap);
		outerror.close();

		// Scripting logs 1
		writeln("\n------------------------------");
		writeln("Bounds on # of cuts = ", nump, " with", data.p);
		writeln("Error = ", error, " (out of ", data.N, " instances)");
		writeln("Accuracy = ", accuracy);
		writeln("Solving time = ", solvetime, " ms (milliseconds)");
		writeln("\nSolution status code = ", status);
		writeln("LB on error =  ", lberr);
		writeln("Relative objective gap = ", relgap);
		writeln("\nSelected variables:");
		
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
		varinfile.readline();	// skip a header
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
		 			var minxjnew = Opl.intValue(myitem[3]);
		 			var maxxjnew = Opl.intValue(myitem[4]);
		 			if ((bcleft <= minxjnew) && (bcright >= maxxjnew)) {	// cover [min,max]
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
		writeln("\nNumber of selected variables = ", numselall, " (", numselcont, " continuous + ", numselcat, " categorical)");
		writeln("------------------------------");
	}
	else
		writeln("No solution");
		
	opl.end();
	data.end(); 
	def.end(); 
	cplex.end(); 
	source.end();

	// Engine log (exported)
	var inlog = new IloOplInputFile("tmp/current-engine.log");
	while (!inlog.eof) {
		outlog.writeln(inlog.readline());
	}
	inlog.close();
	outlog.close();
}