import ph7;
static import std.conv;
import vibe.http.server;
import std.string: toStringz;
import std.stdio;

string getType(ph7_value *pVal)
{
	string zType = "x3";
	if( pVal.iFlags & MEMOBJ_NULL ){
		zType = "null";
	}else if( pVal.iFlags & MEMOBJ_INT ){
		zType = "int";
	}else if( pVal.iFlags & MEMOBJ_REAL ){
		zType = "float";
	}else if( pVal.iFlags & MEMOBJ_STRING ){
		zType = "string";
	}else if( pVal.iFlags & MEMOBJ_BOOL ){
		zType = "bool";
	}else if( pVal.iFlags & MEMOBJ_HASHMAP ){
		zType = "array";
	}else if( pVal.iFlags & MEMOBJ_OBJ ){
		zType = "object";
	}else if( pVal.iFlags & MEMOBJ_RES ){
		zType = "resource";
	}
	return zType;
}

string response;
//extern(C) static int setHeaders(ph7_context *pCtx, uint nOutputLen, void *args/* Unused */){
extern(C) static int setHeaders(ph7_context *pCtx, int nArg, ph7_value **apArg/* Unused */){
	int i;
	if( nArg < 1 ){
		/* Missing arguments,return false */
		ph7_result_bool(pCtx,0);
		return DPP_ENUM_SXRET_OK;
	}
	
	ph7_value *pObj;
	pObj = apArg[0];
	int nLen;
	const char* p = ph7_value_to_string(apArg[0],&nLen);
	string output = p[0..nLen].idup ~ '\n';
	writeln(getType(apArg[0]));
	writeln(apArg[0].iFlags);
	writeln(output);
	
	ph7_result_bool(pCtx,1);
    return 0;
} //int ph7_create_function(ph7_vm*, const(char)*, int function(ph7_context*, int, ph7_value**), void*) @nogc nothrow;
extern(C) static int Output_Consumer(const void *pOutput, uint nOutputLen, void *pUserData/* Unused */){
    char * p = cast(char*)pOutput;
    string output = p[0..nOutputLen].idup ~ '\n';
    response ~= output;
    return 0;
}
void runPHP(string code, HTTPServerRequest req, HTTPServerResponse res){
    response="";
    ph7 *pEngine;
    ph7_vm *pVm;
    int rc;

    rc = ph7_init(&pEngine);
    if( rc != 0 ){
        /*
         * If the supplied memory subsystem is so sick that we are unable
         * to allocate a tiny chunk of memory, there is no much we can do here.
         */
        throw new Exception("Error while allocating a new PH7 engine instance");
    }
    rc = ph7_compile_file(
        pEngine,  /* PH7 engine */
        toStringz(code), /* PHP test program */
        &pVm,     /* OUT: Compiled PHP program */
        0         /* IN: Compile flags */
        );
    
    rc = ph7_vm_config(pVm, 
        DPP_ENUM_PH7_VM_CONFIG_OUTPUT, 
        &Output_Consumer,    /* Output Consumer callback */
        0                   /* Callback private data */
        );

        string method = std.conv.to!string(req.method);
        setServerAttr(pVm, "REQUEST_METHOD", method);
        if(req.queryString.length>0){
            setServerAttr(pVm, "QUERY_STRING", req.queryString);
            foreach(string key, string val; req.query){
                ph7_vm_config(pVm,DPP_ENUM_PH7_VM_CONFIG_GET_ATTR,toStringz(key),toStringz(val),-1);    
            }
        }
        foreach(string key, string val; req.form){
            ph7_vm_config(pVm,DPP_ENUM_PH7_VM_CONFIG_POST_ATTR,toStringz(key),toStringz(val),-1);    
        }
        foreach(string key, string val; req.headers){
            ph7_vm_config(pVm,DPP_ENUM_PH7_VM_CONFIG_HEADER_ATTR,toStringz(key),toStringz(val),-1);    
        }
        string[string] cookies;
        @safe int cook(string key, string val){
            cookies[key]=val;
            return 0;
        }
        req.cookies.opApply(&cook);
        foreach(key, val; cookies){
            ph7_vm_config(pVm,DPP_ENUM_PH7_VM_CONFIG_COOKIE_ATTR,toStringz(key),toStringz(val),-1);    
        }

        ph7_create_function(pVm, "header".toStringz, &setHeaders, null);

    int zero = 0;
    ph7_vm_exec(pVm, &zero);
    ph7_vm_release(pVm);
    ph7_release(pEngine);
    res.writeBody(response, "text/html");
}

int setServerAttr(ph7_vm* pVm, string key, string val){
    int rc = ph7_vm_config(pVm,
         DPP_ENUM_PH7_VM_CONFIG_SERVER_ATTR,
         toStringz(key),
         toStringz(val),
         -1
         );
    return rc;
}