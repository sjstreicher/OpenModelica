/*
 * This file is part of OpenModelica.
 *
 * Copyright (c) 1998-CurrentYear, Linköping University,
 * Department of Computer and Information Science,
 * SE-58183 Linköping, Sweden.
 *
 * All rights reserved.
 *
 * THIS PROGRAM IS PROVIDED UNDER THE TERMS OF GPL VERSION 3 
 * AND THIS OSMC PUBLIC LICENSE (OSMC-PL). 
 * ANY USE, REPRODUCTION OR DISTRIBUTION OF THIS PROGRAM CONSTITUTES RECIPIENT'S  
 * ACCEPTANCE OF THE OSMC PUBLIC LICENSE.
 *
 * The OpenModelica software and the Open Source Modelica
 * Consortium (OSMC) Public License (OSMC-PL) are obtained
 * from Linköping University, either from the above address,
 * from the URLs: http://www.ida.liu.se/projects/OpenModelica or  
 * http://www.openmodelica.org, and in the OpenModelica distribution. 
 * GNU version 3 is obtained from: http://www.gnu.org/copyleft/gpl.html.
 *
 * This program is distributed WITHOUT ANY WARRANTY; without
 * even the implied warranty of  MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE, EXCEPT AS EXPRESSLY SET FORTH
 * IN THE BY RECIPIENT SELECTED SUBSIDIARY LICENSE CONDITIONS
 * OF OSMC-PL.
 *
 * See the full OSMC Public License conditions for more details.
 *
 */

encapsulated package ClassLoader
" file:        ClassLoader.mo
  package:     ClassLoader
  description: Loading of classes from $OPENMODELICALIBRARY.

  RCS: $Id$

  This module loads classes from $OPENMODELICALIBRARY. It exports several functions:
  loadClass function
  loadModel function
  loadFile function"

public import Absyn;

protected import Config;
protected import Debug;
protected import Error;
protected import Flags;
protected import List;
protected import Parser;
protected import System;
protected import Util;

protected uniontype PackageOrder
  record CLASSPART
    Absyn.ClassPart cp;
  end CLASSPART;
  record ELEMENT
    Absyn.ElementItem element;
    Boolean pub "public";
  end ELEMENT;
  record CLASSLOAD
    String cl;
  end CLASSLOAD;
end PackageOrder;

public function loadClass
"function: loadClass
  This function takes a \'Path\' and the $OPENMODELICALIBRARY as a string
  and tries to load the class from the path.
  If the classname is qualified, the complete package is loaded.
  E.g. load_class(Modelica.SIunits.Voltage) -> whole Modelica package loaded."
  input Absyn.Path inPath;
  input list<String> priorityList;
  input String modelicaPath;
  input Option<String> encoding;
  output Absyn.Program outProgram;
algorithm
  outProgram := matchcontinue (inPath,priorityList,modelicaPath,encoding)
    local
      String gd,classname,mp,pack;
      list<String> mps;
      Absyn.Program p;
      Absyn.Path rest;
    /* Simple names: Just load the file if it can be found in $OPENMODELICALIBRARY */
    case (Absyn.IDENT(name = classname),_,mp,_)
      equation
        gd = System.groupDelimiter();
        mps = System.strtok(mp, gd);
        p = loadClassFromMps(classname, priorityList, mps, encoding);
      then
        p;
    /* Qualified names: First check if it is defined in a file pack.mo */
    case (Absyn.QUALIFIED(name = pack,path = rest),_,mp,_)
      equation
        gd = System.groupDelimiter();
        mps = System.strtok(mp, gd);
        p = loadClassFromMps(pack, priorityList, mps, encoding);
      then
        p;
    /* failure */
    else
      equation
        Debug.fprint(Flags.FAILTRACE, "ClassLoader.loadClass failed\n");
      then
        fail();
  end matchcontinue;
end loadClass;

protected function existRegularFile
"function: existRegularFile
  Checks if a file exists"
  input String filename;
algorithm
  true := System.regularFileExists(filename);
end existRegularFile;

public function existDirectoryFile
"function: existDirectoryFile
  Checks if a directory exist"
  input String filename;
algorithm
  true := System.directoryExists(filename);
end existDirectoryFile;

protected function loadClassFromMps
"Loads a class or classes from a set of paths in OPENMODELICALIBRARY"
  input String id;
  input list<String> prios;
  input list<String> mps;
  input Option<String> encoding;
  output Absyn.Program outProgram;
protected
  String mp,name;
  Boolean isDir;
  Absyn.Class cl;
  Absyn.TimeStamp ts;
algorithm
  (mp,name,isDir) := System.getLoadModelPath(id,prios,mps);
  // print("System.getLoadModelPath: " +& id +& " {" +& stringDelimitList(prios,",") +& "} " +& stringDelimitList(mps,",") +& " => " +& mp +& " " +& name +& " " +& boolString(isDir));
  Config.setLanguageStandardFromMSL(name);
  cl := loadClassFromMp(id, mp, name, isDir, encoding);
  ts := Absyn.getNewTimeStamp();
  outProgram := Absyn.PROGRAM({cl},Absyn.TOP(),ts);
end loadClassFromMps;

protected function loadClassFromMp
  input String id "the actual class name";
  input String path;
  input String name;
  input Boolean isDir;
  input Option<String> optEncoding;
  output Absyn.Class outClass;
algorithm
  outClass := match (id,path,name,isDir,optEncoding)
    local
      String pd,encoding,encodingfile;
      Absyn.Class cl;

    case (_,_,_,false,_)
      equation
        pd = System.pathDelimiter();
        /* Check for path/package.encoding; OpenModelica extension */
        encodingfile = stringAppendList({path,pd,"package.encoding"});
        encoding = System.trimChar(System.trimChar(Debug.bcallret1(System.regularFileExists(encodingfile),System.readFile,encodingfile,Util.getOptionOrDefault(optEncoding,"UTF-8")),"\n")," ");
        cl = parsePackageFile(path +& pd +& name,encoding,false,Absyn.TOP(),id);
      then
        cl;

    case (_,_,_,true,_)
      equation
        /* Check for path/package.encoding; OpenModelica extension */
        pd = System.pathDelimiter();
        encodingfile = stringAppendList({path,pd,name,pd,"package.encoding"});
        encoding = System.trimChar(System.trimChar(Debug.bcallret1(System.regularFileExists(encodingfile),System.readFile,encodingfile,Util.getOptionOrDefault(optEncoding,"UTF-8")),"\n")," ");
        cl = loadCompletePackageFromMp(id, name, path, encoding, Absyn.TOP(), Error.getNumErrorMessages());
      then
        cl;
  end match;
end loadClassFromMp;

protected function loadCompletePackageFromMp
"function: loadCompletePackageFromMp
  Loads a whole package from the ModelicaPaths defined in OPENMODELICALIBRARY"
  input String id "actual class identifier";
  input Absyn.Ident inIdent;
  input String inString;
  input String encoding;
  input Absyn.Within inWithin;
  input Integer numError;
  output Absyn.Class cl;
algorithm
  cl := matchcontinue (id,inIdent,inString,encoding,inWithin,numError)
    local
      String pd,mp_1,packagefile,orderfile,pack,mp,name,str;
      Absyn.Class cl;
      Absyn.Within within_;
      list<String> tv;
      Boolean pp,fp,ep;
      Absyn.Restriction r;
      list<Absyn.NamedArg> ca;
      list<Absyn.ClassPart> cp;
      Option<String> cmt;
      Absyn.Info info;
      Absyn.Path path;
      Absyn.Within w2;
      list<PackageOrder> reverseOrder;
    case (_,pack,mp,_,within_,_)
      equation
        pd = System.pathDelimiter();
        mp_1 = stringAppendList({mp,pd,pack});
        packagefile = stringAppendList({mp_1,pd,"package.mo"});
        orderfile = stringAppendList({mp_1,pd,"package.order"});
        existRegularFile(packagefile);
        (cl as Absyn.CLASS(name,pp,fp,ep,r,Absyn.PARTS(tv,ca,cp,cmt),info)) = parsePackageFile(packagefile,encoding,true,within_,id);
        reverseOrder = getPackageContentNames(cl, orderfile, mp_1, Error.getNumErrorMessages());
        path = Absyn.joinWithinPath(within_,Absyn.IDENT(id));
        w2 = Absyn.WITHIN(path);
        cp = List.fold3(reverseOrder, loadCompletePackageFromMp2, mp_1, encoding, w2, {});
      then Absyn.CLASS(name,pp,fp,ep,r,Absyn.PARTS(tv,ca,cp,cmt),info);
    case (_,pack,mp,_,within_,_)
      equation
        true = numError == Error.getNumErrorMessages();
        str = "loadCompletePackageFromMp failed for unknown reason: mp=" +& mp +& " pack=" +& pack;
        Error.addMessage(Error.INTERNAL_ERROR, {str});
      then fail();
  end matchcontinue;
end loadCompletePackageFromMp;

protected function mergeBefore
  input Absyn.ClassPart cp;
  input list<Absyn.ClassPart> cps;
  output list<Absyn.ClassPart> ocp;
algorithm
  ocp := match (cp,cps)
    local
      list<Absyn.ElementItem> ei1,ei2,ei;
      list<Absyn.ClassPart> rest;
    case (Absyn.PUBLIC(ei1),Absyn.PUBLIC(ei2)::rest)
      equation
        ei = listAppend(ei1,ei2);
      then Absyn.PUBLIC(ei)::rest;
    case (Absyn.PROTECTED(ei1),Absyn.PROTECTED(ei2)::rest)
      equation
        ei = listAppend(ei1,ei2);
      then Absyn.PROTECTED(ei)::rest;
    case (_,cps) then cp::cps;
  end match;
end mergeBefore;

protected function loadCompletePackageFromMp2
"function: loadCompletePackageFromMp
  Loads a whole package from the ModelicaPaths defined in OPENMODELICALIBRARY"
  input PackageOrder po "mo-file or directory";
  input String mp;
  input String encoding;
  input Absyn.Within w1 "With the parent added";
  input list<Absyn.ClassPart> acc;
  output list<Absyn.ClassPart> cps;
algorithm
  cps := matchcontinue (po,mp,encoding,w1,acc)
    local
      Absyn.ElementItem ei;
      String pd,file,id;
      Absyn.ClassPart cp;
      Absyn.Class cl;
      
    case (CLASSPART(cp),_,_,_,_)
      equation
        cps = mergeBefore(cp,acc);
      then cps;
      
    case (ELEMENT(ei,true),_,_,_,_)
      equation
        cps = mergeBefore(Absyn.PUBLIC({ei}),acc);
      then cps;

    case (ELEMENT(ei,false),_,_,_,_)
      equation
        cps = mergeBefore(Absyn.PROTECTED({ei}),acc);
      then cps;

    case (CLASSLOAD(id),_,_,_,_)
      equation
        pd = System.pathDelimiter();
        true = System.directoryExists(mp +& pd +& id);
        cl = loadCompletePackageFromMp(id,id,mp,encoding,w1,Error.getNumErrorMessages());
        ei = Absyn.makeClassElement(cl);
        cps = mergeBefore(Absyn.PUBLIC({ei}),acc);
      then cps;

    case (CLASSLOAD(id),_,_,_,_)
      equation
        pd = System.pathDelimiter();
        false = System.directoryExists(mp +& pd +& id);
        file = mp +& pd +& id +& ".mo";
        true = System.regularFileExists(file);
        cl = parsePackageFile(file,encoding,false,w1,id);
        ei = Absyn.makeClassElement(cl);
        cps = mergeBefore(Absyn.PUBLIC({ei}),acc);
      then cps;
    
  end matchcontinue;
end loadCompletePackageFromMp2;

public function loadFile
"function loadFile
  author: x02lucpo
  load the file or the directory structure if the file is named package.mo"
  input String name;
  input String encoding;
  output Absyn.Program outProgram;
algorithm
  outProgram := matchcontinue (name,encoding)
    local
      String dir,filename,cname,prio,mp;
      Absyn.Program p1;
      list<String> rest;

    case (_,_)
      equation
        true = System.regularFileExists(name);
        (dir,"package.mo") = Util.getAbsoluteDirectoryAndFile(name);
        cname::rest = System.strtok(List.last(System.strtok(dir,"/"))," ");
        prio = stringDelimitList(rest, " ");
        prio = Util.if_(stringEq(prio,""), "default", prio);
        mp = dir +& "/../";
        p1 = loadClass(Absyn.IDENT(cname),{prio},mp,SOME(encoding));
      then p1;

    case (_,_)
      equation
        true = System.regularFileExists(name);
        (dir,filename) = Util.getAbsoluteDirectoryAndFile(name);
        false = stringEq(filename,"package.mo");
        p1 = Parser.parse(name,encoding);
      then p1;

    // faliling
    else
      equation
        Debug.fprint(Flags.FAILTRACE, "ClassLoader.loadFile failed: "+&name+&"\n");
      then
        fail();
  end matchcontinue;
end loadFile;

public function parsePackageFile
  "Parses a file containing a single class that matches the within"
  input String name;
  input String encoding;
  input Boolean expectPackage;
  input Absyn.Within w1 "Expected within of the package";
  input String pack "Expected name of the package";
  output Absyn.Class outClass;
algorithm
  outClass := matchcontinue (name,encoding,expectPackage,w1,pack)
    local
      Absyn.Class cl;
      list<Absyn.Class> cs;
      Absyn.Within w2;
      Absyn.TimeStamp ts;
      list<String> classNames;
      Absyn.Info info;
      String str,s1,s2,cname;
      Absyn.ClassDef body;

    case (_,_,_,_,_)
      equation
        true = System.regularFileExists(name);
        Absyn.PROGRAM(cs,w2,ts) = Parser.parse(name,encoding);
        classNames = List.map(cs, Absyn.getClassName);
        str = stringDelimitList(classNames,", ");
        Error.assertionOrAddSourceMessage(listLength(cs)==1, Error.LIBRARY_ONE_PACKAGE_PER_FILE, {str}, Absyn.INFO(name,true,0,0,0,0,ts));
        cl::{} = cs;
        Absyn.CLASS(name=cname,body=body,info=info) = cl;
        Error.assertionOrAddSourceMessage(stringEqual(cname,pack), Error.LIBRARY_UNEXPECTED_NAME, {pack,cname}, info);
        s1 = Absyn.withinString(w1);
        s2 = Absyn.withinString(w2);
        Error.assertionOrAddSourceMessage(Absyn.withinEqual(w1,w2) or Config.languageStandardAtMost(Config.MODELICA_1_X()), Error.LIBRARY_UNEXPECTED_WITHIN, {s1,s2}, info);
        Error.assertionOrAddSourceMessage((not expectPackage) or Absyn.isParts(body), Error.LIBRARY_EXPECTED_PARTS, {pack}, info);
      then cl;

    // faliling
    else
      equation
        Debug.fprint(Flags.FAILTRACE, "ClassLoader.parsePackageFile failed: "+&name+&"\n");
      then
        fail();
  end matchcontinue;
end parsePackageFile;

protected function getPackageContentNames
  "Gets the names of packages to load before the package.mo, and the ones to load after"
  input Absyn.Class cl;
  input String filename;
  input String mp;
  input Integer numError;
  output list<PackageOrder> po "reverse";
algorithm
  (po) := matchcontinue (cl,filename,mp,numError)
    local
      String contents;
      list<String> namesToFind,    mofiles, subdirs;
      list<Absyn.ClassPart> cp;
      Absyn.Info info;
    case (Absyn.CLASS(body=Absyn.PARTS(classParts=cp),info=info),_,_,_)
      equation
        true = System.regularFileExists(filename);
        contents = System.readFile(filename);
        namesToFind = System.strtok(contents, "\n");
        namesToFind = List.removeOnTrue("",stringEqual,List.map(namesToFind,System.trimWhitespace));
        po = getPackageContentNamesinParts(namesToFind,cp,{});
        List.map2_0(po,checkPackageOrderFilesExist,mp,info);
      then po;

    case (Absyn.CLASS(body=Absyn.PARTS(classParts=cp),info=info),_,_,_)
      equation
        false = System.regularFileExists(filename);
        mofiles = List.map(System.moFiles(mp), Util.removeLast3Char) "Here .mo files in same directory as package.mo should be loaded as sub-packages";
        subdirs = System.subDirectories(mp);
        subdirs = List.filter1OnTrue(subdirs, existPackage, mp);
        mofiles = List.sort(listAppend(subdirs,mofiles), Util.strcmpBool);
        po = listAppend(List.map(cp, makeClassPart),List.map(mofiles, makeClassLoad));
      then po;
    
    case (Absyn.CLASS(info=info),_,_,_)
      equation
        true = numError == Error.getNumErrorMessages();
        Error.addSourceMessage(Error.INTERNAL_ERROR,{"getPackageContentNames failed for unknown reason"},info);
      then fail();
  end matchcontinue;
end getPackageContentNames;

protected function makeClassPart
  input Absyn.ClassPart part;
  output PackageOrder po;
algorithm
  po := CLASSPART(part);
end makeClassPart;

protected function makeElement
  input Absyn.ElementItem el;
  input Boolean pub;
  output PackageOrder po;
algorithm
  po := ELEMENT(el,pub);
end makeElement;

protected function makeClassLoad
  input String str;
  output PackageOrder po;
algorithm
  po := CLASSLOAD(str);
end makeClassLoad;

protected function checkPackageOrderFilesExist
  input PackageOrder po;
  input String mp;
  input Absyn.Info info;
algorithm
  _ := match (po,mp,info)
    local
      String pd,str;
    case (CLASSLOAD(str),_,_)
      equation
        pd = System.pathDelimiter();
        Error.assertionOrAddSourceMessage(System.directoryExists(mp +& pd +& str) or System.regularFileExists(mp +& pd +& str +& ".mo"),Error.PACKAGE_ORDER_FILE_NOT_FOUND,{str},info);
      then ();
    else ();
  end match;  
end checkPackageOrderFilesExist;

protected function existPackage
  input String name;
  input String mp;
  output Boolean b;
protected
  String pd;
algorithm
  pd := System.pathDelimiter();
  b := System.regularFileExists(mp +& pd +& name +& pd +& "package.mo"); 
end existPackage;

protected function getPackageContentNamesinParts
  input list<String> inNamesToSort;
  input list<Absyn.ClassPart> cps;
  input list<PackageOrder> acc;
  output list<PackageOrder> outOrder "reverse";
algorithm
  outOrder := match (inNamesToSort,cps,acc)
    local
      list<Absyn.ClassPart> rcp;
      list<Absyn.ElementItem> elts;
      list<String> namesToSort;
      Absyn.ClassPart cp;
    case (namesToSort,{},_)
      equation
        outOrder = listAppend(List.mapReverse(namesToSort,makeClassLoad),acc);
      then outOrder;
    case (namesToSort,Absyn.PUBLIC(elts)::rcp,_)
      equation
        (outOrder,namesToSort) = getPackageContentNamesinElts(namesToSort,elts,acc,true);
        (outOrder) = getPackageContentNamesinParts(namesToSort,rcp,outOrder);
      then outOrder;
    case (namesToSort,Absyn.PROTECTED(elts)::rcp,_)
      equation
        (outOrder,namesToSort) = getPackageContentNamesinElts(namesToSort,elts,acc,false);
        (outOrder) = getPackageContentNamesinParts(namesToSort,rcp,outOrder);
      then outOrder;
    case (namesToSort,cp::rcp,_)
      equation
        (outOrder) = getPackageContentNamesinParts(namesToSort,rcp,CLASSPART(cp)::acc);
      then outOrder;
  end match;
end getPackageContentNamesinParts;

protected function getPackageContentNamesinElts
  input list<String> inNamesToSort;
  input list<Absyn.ElementItem> inElts;
  input list<PackageOrder> po;
  input Boolean pub;
  output list<PackageOrder> outOrder;
  output list<String> outNames;
algorithm
  (outOrder,outNames) := match (inNamesToSort,inElts,po,pub)
    local
      String name1,name2;
      list<String> namesToSort,names,compNames;
      list<Absyn.ElementItem> elts;
      Boolean b;
      Absyn.Info info;
      list<Absyn.ComponentItem> comps;
      Absyn.ElementItem ei;
      PackageOrder orderElt,load;
    case (namesToSort,{},po,pub) then (po,namesToSort);

    case (name1::namesToSort,(ei as Absyn.ELEMENTITEM(Absyn.ELEMENT(specification=Absyn.COMPONENTS(components=comps),info=info)))::elts,_,_)
      equation
        compNames = List.map(comps,Absyn.componentName);
        (names,b) = matchCompNames(inNamesToSort,compNames,info);
        orderElt = Util.if_(b, makeElement(ei,pub), makeClassLoad(name1));
        (outOrder,names) = getPackageContentNamesinElts(names,Util.if_(b,elts,inElts),orderElt :: po,pub);
      then (outOrder,names);

    case (name1::namesToSort,(ei as Absyn.ELEMENTITEM(Absyn.ELEMENT(specification=Absyn.CLASSDEF(class_=Absyn.CLASS(name=name2,info=info)))))::elts,_,_)
      equation
        load = makeClassLoad(name1);
        b = name1 ==& name2;
        Error.assertionOrAddSourceMessage(not Debug.bcallret2(b,listMember,load,po,false), Error.PACKAGE_MO_NOT_IN_ORDER, {name2}, info);
        orderElt = Util.if_(b, makeElement(ei,pub), load);
        (outOrder,names) = getPackageContentNamesinElts(namesToSort,Util.if_(b,elts,inElts),orderElt :: po, pub);
      then (outOrder,names);

    case ({},(ei as Absyn.ELEMENTITEM(Absyn.ELEMENT(specification=Absyn.CLASSDEF(class_=Absyn.CLASS(name=name2,info=info)))))::elts,_,_)
      equation
        load = makeClassLoad(name2);
        Error.assertionOrAddSourceMessage(not listMember(load,po), Error.PACKAGE_MO_NOT_IN_ORDER, {name2}, info);
        Error.addSourceMessage(Error.FOUND_ELEMENT_NOT_IN_ORDER_FILE, {name2}, info);
      then fail();

    case ({},Absyn.ELEMENTITEM(Absyn.ELEMENT(specification=Absyn.COMPONENTS(components=Absyn.COMPONENTITEM(component=Absyn.COMPONENT(name=name2))::_),info=info))::elts,_,_)
      equation
        load = makeClassLoad(name2);
        Error.assertionOrAddSourceMessage(not listMember(load,po), Error.PACKAGE_MO_NOT_IN_ORDER, {name2}, info);
        Error.addSourceMessage(Error.FOUND_ELEMENT_NOT_IN_ORDER_FILE, {name2}, info);
      then fail();

    case (namesToSort,ei::elts,_,_)
      equation
        (outOrder,names) = getPackageContentNamesinElts(namesToSort,elts,ELEMENT(ei,pub) :: po, pub);
      then (outOrder,names);
  end match;
end getPackageContentNamesinElts;

protected function matchCompNames
  input list<String> names;
  input list<String> comps;
  input Absyn.Info info;
  output list<String> outNames;
  output Boolean matchedNames;
algorithm
  (outNames,matchedNames) := matchcontinue (names,comps,info)
    local
      Boolean b;
      String n1,n2;
      list<String> rest1,rest2;
    case (_,{},_) then (names,true);
    case (n1::rest1,n2::rest2,_)
      equation
        true = n1 ==& n2;
        (rest1,b) = matchCompNames(rest1,rest2,info);
        Error.assertionOrAddSourceMessage(b,Error.ORDER_FILE_COMPONENTS, {}, info);
      then (rest1,true);
    case (n1::rest1,n2::rest2,_)
      equation
        false = n1 ==& n2;
      then (rest1,false);
  end matchcontinue;
end matchCompNames;

protected function packageOrderName
  input PackageOrder ord;
  output String name;
algorithm
  name := match ord
    case CLASSLOAD(name) then name;
    else "#";
  end match;
end packageOrderName;

end ClassLoader;

