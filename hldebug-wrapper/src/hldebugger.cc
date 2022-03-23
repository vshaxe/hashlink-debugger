#include "hl.h"
#include <napi.h>
#include <node_buffer.h>

extern "C" {
	bool hl_debug_start(int pid);
	bool hl_debug_stop(int pid);
	bool hl_debug_breakpoint(int pid);
	bool hl_debug_read(int pid, vbyte* addr, vbyte* buffer, int size);
	bool hl_debug_write(int pid, vbyte* addr, vbyte* buffer, int size);
	bool hl_debug_flush(int pid, vbyte* addr, int size);
	int hl_debug_wait(int pid, int* thread, int timeout);
	bool hl_debug_resume(int pid, int thread);
	void* hl_debug_read_register(int pid, int thread, int reg, bool is64);
	bool hl_debug_write_register(int pid, int thread, int reg, void* value, bool is64);
}

using namespace Napi;

inline Napi::String data_to_napi_string(Napi::Env env, void* in_data, int in_len) {
	return Napi::String::New(env, (const char16_t*)in_data, in_len/2);
}

inline std::u16string data_from_napi_string(Napi::String napi_string) {
	return napi_string.Utf16Value();
}

Napi::Boolean debugStart(const Napi::CallbackInfo& info) {
	Napi::Env env = info.Env();

	int pid = info[0].As<Napi::Number>().Int32Value();

	return Napi::Boolean::New(env, hl_debug_start(pid));
}

Napi::Boolean debugStop(const Napi::CallbackInfo& info) {
	Napi::Env env = info.Env();

	int pid = info[0].As<Napi::Number>().Int32Value();

	return Napi::Boolean::New(env, hl_debug_stop(pid));
}

Napi::Boolean debugBreakpoint(const Napi::CallbackInfo& info) {
	Napi::Env env = info.Env();

	int pid = info[0].As<Napi::Number>().Int32Value();

	return Napi::Boolean::New(env, hl_debug_breakpoint(pid));
}

Napi::String debugRead(const Napi::CallbackInfo& info) {
	Napi::Env env = info.Env();

	int pid = info[0].As<Napi::Number>().Int32Value();
	std::u16string ptr = data_from_napi_string(info[1].ToString());
	int size = info[2].As<Napi::Number>().Int32Value();

	int bufsize = size;
	if (bufsize % 2 == 1)
		bufsize++;
	vbyte* rbuf = (vbyte*) malloc(bufsize);
	rbuf[bufsize-1] = 0;
	Napi::Boolean r = Napi::Boolean::New(env, hl_debug_read(pid, *(vbyte**)ptr.c_str(), rbuf, size));
	Napi::String ostr = data_to_napi_string(env, rbuf, bufsize);
	free(rbuf);

	return ostr;
}

Napi::Boolean debugWrite(const Napi::CallbackInfo& info) {
	Napi::Env env = info.Env();

	int pid = info[0].As<Napi::Number>().Int32Value();
	std::u16string ptr = data_from_napi_string(info[1].ToString());
	std::u16string buffer = data_from_napi_string(info[2].ToString());
	int size = info[3].As<Napi::Number>().Int32Value();

	bool r = hl_debug_write(pid, *(vbyte**)ptr.c_str(), (vbyte*) buffer.c_str(), size);
	return Napi::Boolean::New(env, r);
}

Napi::Boolean debugFlush(const Napi::CallbackInfo& info) {
	Napi::Env env = info.Env();

	int pid = info[0].As<Napi::Number>().Int32Value();
	std::u16string ptr = data_from_napi_string(info[1].ToString());
	int size = info[2].As<Napi::Number>().Int32Value();

	Napi::Boolean r = Napi::Boolean::New(env, hl_debug_flush(pid, *(vbyte**)ptr.c_str(), size));
	return r;
}

Napi::Buffer<int> debugWait(const Napi::CallbackInfo& info) {
	Napi::Env env = info.Env();

	int pid = info[0].As<Napi::Number>().Int32Value();
	int size = info[1].As<Napi::Number>().Int32Value();
	
	int threadId;
	int r = hl_debug_wait(pid, &threadId, size);
	
	Napi::Buffer<int> buffer = Napi::Buffer<int>::New(env, 2);
	buffer.Data()[0] = r;
	buffer.Data()[1] = threadId;
	return buffer;
}

Napi::Boolean debugResume(const Napi::CallbackInfo& info) {
	Napi::Env env = info.Env();
	int pid = info[0].As<Napi::Number>().Int32Value();
	int tid = info[1].As<Napi::Number>().Int32Value();
	return Napi::Boolean::New(env, hl_debug_resume(pid, tid));
}

Napi::String debugReadRegister(const Napi::CallbackInfo& info) {
	Napi::Env env = info.Env();
	int pid = info[0].As<Napi::Number>().Int32Value();
	int tid = info[1].As<Napi::Number>().Int32Value();
	int reg = info[2].As<Napi::Number>().Int32Value();
	bool is64 = info[3].As<Napi::Boolean>().Value();
	void* r = hl_debug_read_register(pid, tid, reg, is64);
	Napi::String ostr;
	if(reg == 3)
		ostr = data_to_napi_string(env, &r, 2);
	else
		ostr = data_to_napi_string(env, &r, 8);
	return ostr;
}

Napi::Boolean debugWriteRegister(const Napi::CallbackInfo& info) {
	Napi::Env env = info.Env();

	int pid = info[0].As<Napi::Number>().Int32Value();
	int tid = info[1].As<Napi::Number>().Int32Value();
	int reg = info[2].As<Napi::Number>().Int32Value();
	std::u16string buffer = data_from_napi_string(info[3].ToString());
	bool is64 = info[4].As<Napi::Boolean>().Value();

	return Napi::Boolean::New(env, hl_debug_write_register(pid, tid, reg, *(vbyte**) buffer.c_str(), is64));
}

Napi::Object Init(Napi::Env env, Napi::Object exports) {
	exports.Set(Napi::String::New(env, "debugStart"), Napi::Function::New(env, debugStart));
	exports.Set(Napi::String::New(env, "debugStop"), Napi::Function::New(env, debugStop));
	exports.Set(Napi::String::New(env, "debugBreakpoint"), Napi::Function::New(env, debugBreakpoint));
	exports.Set(Napi::String::New(env, "debugRead"), Napi::Function::New(env, debugRead));
	exports.Set(Napi::String::New(env, "debugWrite"), Napi::Function::New(env, debugWrite));
	exports.Set(Napi::String::New(env, "debugFlush"), Napi::Function::New(env, debugFlush));
	exports.Set(Napi::String::New(env, "debugWait"), Napi::Function::New(env, debugWait));
	exports.Set(Napi::String::New(env, "debugResume"), Napi::Function::New(env, debugResume));
	exports.Set(Napi::String::New(env, "debugReadRegister"), Napi::Function::New(env, debugReadRegister));
	exports.Set(Napi::String::New(env, "debugWriteRegister"), Napi::Function::New(env, debugWriteRegister));
	return exports;
}

NODE_API_MODULE(node_debugger, Init)
