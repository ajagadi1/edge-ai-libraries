/*
 * Windows-specific GenTL wrapper implementation
 * This file is derived from gentl_wrapper_linux.cc for Windows platform
 */

#include "gentl_wrapper.h"
#include "exception.h"

#include <windows.h>
#include <string>
#include <vector>
#include <sstream>
#include <algorithm>

namespace rcg
{

namespace
{

/**
 * Split string by delimiter
 */
std::vector<std::string> split(const std::string &s, char delim)
{
  std::vector<std::string> list;
  std::stringstream ss(s);
  std::string item;

  while (std::getline(ss, item, delim))
  {
    if (!item.empty())
    {
      list.push_back(item);
    }
  }

  return list;
}

/**
 * Get list of paths from GENICAM_GENTL64_PATH or GENICAM_GENTL32_PATH
 */
std::vector<std::string> getAvailableGenTLPaths()
{
  std::vector<std::string> ret;

  // Try 64-bit path first
  char* path_env = nullptr;
  size_t len = 0;
  
#ifdef _WIN64
  _dupenv_s(&path_env, &len, "GENICAM_GENTL64_PATH");
#else
  _dupenv_s(&path_env, &len, "GENICAM_GENTL32_PATH");
#endif

  if (path_env != nullptr)
  {
    std::string path(path_env);
    free(path_env);
    
    // Split by semicolon (Windows path separator)
    ret = split(path, ';');
  }
  else
  {
    // Fallback: try the other architecture
#ifdef _WIN64
    _dupenv_s(&path_env, &len, "GENICAM_GENTL32_PATH");
#else
    _dupenv_s(&path_env, &len, "GENICAM_GENTL64_PATH");
#endif
    
    if (path_env != nullptr)
    {
      std::string path(path_env);
      free(path_env);
      ret = split(path, ';');
    }
  }

  return ret;
}

}

/**
 * Load GenTL producer library
 */
void *loadGenTLProducer(const char *name)
{
  void *lib = nullptr;

  if (name != nullptr && name[0] != '\0')
  {
    // Try loading the specified library directly
    lib = LoadLibraryA(name);

    if (lib == nullptr)
    {
      // If loading failed, try with .cti extension
      std::string sname = name;
      if (sname.find(".cti") == std::string::npos && 
          sname.find(".CTI") == std::string::npos)
      {
        sname += ".cti";
        lib = LoadLibraryA(sname.c_str());
      }
    }
  }
  else
  {
    // No specific library requested, search in GENICAM_GENTL*_PATH
    std::vector<std::string> pathlist = getAvailableGenTLPaths();

    if (pathlist.empty())
    {
      throw GenTLException("No transport layers found in GENICAM_GENTL64_PATH or GENICAM_GENTL32_PATH");
    }

    // Try loading .cti files from the paths
    for (const auto &path : pathlist)
    {
      WIN32_FIND_DATAA ffd;
      std::string search_pattern = path;
      
      // Ensure path ends with backslash
      if (!search_pattern.empty() && search_pattern.back() != '\\' && search_pattern.back() != '/')
      {
        search_pattern += "\\";
      }
      search_pattern += "*.cti";
      
      HANDLE hFind = FindFirstFileA(search_pattern.c_str(), &ffd);
      
      if (hFind != INVALID_HANDLE_VALUE)
      {
        do
        {
          std::string full_path = path;
          if (!full_path.empty() && full_path.back() != '\\' && full_path.back() != '/')
          {
            full_path += "\\";
          }
          full_path += ffd.cFileName;
          
          lib = LoadLibraryA(full_path.c_str());
          
          if (lib != nullptr)
          {
            FindClose(hFind);
            return lib;
          }
        }
        while (FindNextFileA(hFind, &ffd) != 0);
        
        FindClose(hFind);
      }
    }
  }

  if (lib == nullptr)
  {
    DWORD error = GetLastError();
    std::string msg = "Cannot load GenTL producer";
    if (name != nullptr && name[0] != '\0')
    {
      msg += " '";
      msg += name;
      msg += "'";
    }
    msg += " (Error code: ";
    msg += std::to_string(error);
    msg += ")";
    
    throw GenTLException(msg);
  }

  return lib;
}

/**
 * Free GenTL producer library
 */
void freeGenTLProducer(void *lib)
{
  if (lib != nullptr)
  {
    FreeLibrary(static_cast<HMODULE>(lib));
  }
}

/**
 * Get function pointer from GenTL producer library
 */
void *getGenTLFunction(void *lib, const char *name)
{
  if (lib == nullptr)
  {
    throw GenTLException("Invalid library handle");
  }

  void *fn = reinterpret_cast<void*>(GetProcAddress(static_cast<HMODULE>(lib), name));
  
  if (fn == nullptr)
  {
    std::string msg = "Cannot find function '";
    msg += name;
    msg += "' in GenTL producer";
    throw GenTLException(msg);
  }

  return fn;
}

}
