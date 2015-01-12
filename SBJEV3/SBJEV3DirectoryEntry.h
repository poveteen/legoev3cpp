//
//  SBJEV3DirectoryEntry.h
//  Jove's Landing
//
//  Created by David Giovannini on 1/12/15.
//  Copyright (c) 2015 Software by Jove. All rights reserved.
//

#include <vector>
#include <array>
#include <string>

namespace SBJ
{
namespace EV3
{

#define DIREXT std::string("/")
#define EXEEXT std::string(".rbf")
#define DATALOGEXT std::string(".raf")
#define CURRENTDIR std::string("./")
#define PARENTDIR std::string("../")
#define ROOTDIR std::string("/home/root/lms2012/")
#define TOOLDIR std::string("/home/root/lms2012/tools/")
#define SYSDIR std::string("/home/root/lms2012/sys/")
#define SOURCEDIR std::string("/home/root/lms2012/source/")
#define APPDIR std::string("/home/root/lms2012/apps/")
#define PROJDIR std::string("/home/root/lms2012/prjs/")

class DirectoryEntry
{
public:
	static std::vector<DirectoryEntry> read(const char* data, size_t len);

	DirectoryEntry();
	
	DirectoryEntry(const std::string& line);
	
	bool isDirectory() const;
	
	const std::string& name() const { return _name; }
	
	const std::array<uint8_t, 16>& hash() const { return _hash; }
	
	unsigned int size() const { return _size; }
	
	std::string hashStr() const;
	
	std::string simpleName() const;
	
	std::string extension() const;
	
	std::string escapedName() const;
	
	std::string pathRelativeToSys(std::string path) const;
	
private:
	std::array<uint8_t, 16> _hash;
	unsigned int _size;
	std::string _name;
};

}
}
