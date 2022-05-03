#ifdef _WIN32
#include <Windows.h>
#endif
#include <iostream>
#include <memory>
#include <vector>
#include <set>
#include <iostream>
#include <exception>
#include <stdexcept>
#include <cassert>
#include "blelf.h"
#include <LIEF/ELF.hpp>
using namespace std;
using namespace binlex;
using namespace LIEF::ELF;

ELF::ELF(){
    total_exec_sections = 0;

    for (int i = 0; i < BINARY_MAX_SECTIONS; i++){
        sections[i].offset = 0;
        sections[i].size = 0;
        sections[i].data = NULL;
    }
}

bool ELF::Setup(ARCH input_mode){
    switch(input_mode){
        case ARCH::EM_386:
            mode = ARCH::EM_386;
            break;
        case ARCH::EM_X86_64:
            mode = ARCH::EM_X86_64;
            break;
        default:
            mode = ARCH::EM_NONE;
            fprintf(stderr, "[x] unsupported mode.\n");
            return false;
    }
    return true;
}

bool ELF::ReadFile(char *file_path){
    if (FileExists(file_path) == false){
        return false;
    }
    CalculateFileHashes(file_path);
    assert(!tlsh.empty());
    assert(!sha256.empty());
    binary = Parser::parse(file_path);
    if (mode != binary->header().machine_type()){
        fprintf(stderr, "[x] incorrect mode for binary architecture\n");
        return false;
    }
    return ParseSections();
}

bool ELF::ReadBuffer(void *data, size_t size){
    vector<uint8_t> data_v((uint8_t *)data, (uint8_t *)data + size);
    binary = Parser::parse(data_v);
    if (mode != binary->header().machine_type()){
        fprintf(stderr, "[x] incorrect mode for binary architecture\n");
        return false;
    }
    return ParseSections();
}

bool ELF::ParseSections(){
    uint index = 0;
    it_sections local_sections = binary->sections();
    for (auto it = local_sections.begin(); it != local_sections.end(); it++){
        if (it->flags() & (uint64_t)ELF_SECTION_FLAGS::SHF_EXECINSTR){
            sections[index].offset = it->offset();
            sections[index].size = it->original_size();
            sections[index].data = malloc(sections[index].size);
            memset(sections[index].data, 0, sections[index].size);
            vector<uint8_t> data = binary->get_content_from_virtual_address(it->virtual_address(), it->original_size());
            memcpy(sections[index].data, &data[0], sections[index].size);
            it_exported_symbols symbols = binary->exported_symbols();
            for (auto j = symbols.begin(); j != symbols.end(); j++){
                uint64_t tmp_offset = binary->virtual_address_to_offset(j->value());
                 if (tmp_offset > sections[index].offset &&
                    tmp_offset < sections[index].offset + sections[index].size){
                    sections[index].functions.insert(tmp_offset-sections[index].offset);
                }
            }
            index++;
            if (BINARY_MAX_SECTIONS == index)
            {
                fprintf(stderr, "[x] malformed binary, too many executable sections\n");
                return false;
            }
        }
    }
    total_exec_sections = index + 1;
    return true;
}

ELF::~ELF(){
    for (int i = 0; i < total_exec_sections; i++){
        sections[i].offset = 0;
        sections[i].size = 0;
        free(sections[i].data);
        sections[i].functions.clear();
    }
}
