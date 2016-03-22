//
//  FaceBeautifyVideoFilter.cpp
//  Pods
//
//  Created by jing huai on 16/3/18.
//
//

//#include <videocore/filters/Extend/FaceBeautifyVideoFilter.h>
#include "FaceBeautifyVideoFilter.h"
#include <TargetConditionals.h>
#include <Foundation/Foundation.h>

#ifdef TARGET_OS_IPHONE

#include <OpenGLES/ES2/gl.h>
#include <OpenGLES/ES3/gl.h>
#include <videocore/sources/iOS/GLESUtil.h>
#include <videocore/filters/FilterFactory.h>

#endif

namespace videocore {

namespace filters {
    
    bool FaceBeautifyVideoFilter::s_registered = FaceBeautifyVideoFilter::registerFilter();
    
    bool FaceBeautifyVideoFilter::registerFilter() {
        FilterFactory::_register("com.videocore.filters.faceBeautify", []() {return new FaceBeautifyVideoFilter(); });
        return true;
    }
    
    FaceBeautifyVideoFilter::FaceBeautifyVideoFilter()
    : IVideoFilter(), m_initialized(false), m_bound(false)
    {
        
    }
    

    FaceBeautifyVideoFilter::~FaceBeautifyVideoFilter()
    {
        glDeleteProgram(m_program);
        glDeleteVertexArrays(1, &m_vao);
    }
    
    static GLuint loadBMP_custom(const char *imagepath)
    {
        // Data read from the header of the BMP file
        unsigned char header[54]; // Each BMP file begins by a 54-bytes header
        unsigned int dataPos;     // Position in the file where the actual data begins
        unsigned int width, height;
        unsigned int imageSize;   // = width*height*3
        // Actual RGB data
        unsigned char * data;
        
        //Open the file
        FILE *file = fopen(imagepath, "rb");
        if (!file) {
            printf("Image could not be opened");
            return 0;
        }
        
        if ( fread(header, 1, 54, file)!=54 ){ // If not 54 bytes read : problem
            printf("Not a correct BMP filen");
            return false;
        }
        
        if ( header[0]!='B' || header[1]!='M' ){
            printf("Not a correct BMP filen");
            return 0;
        }
        
        // Read ints from the byte array
        dataPos    = *(int*)&(header[0x0A]);
        imageSize  = *(int*)&(header[0x22])*3;
        width      = *(int*)&(header[0x12]);
        height     = *(int*)&(header[0x16]);
        
        // Some BMP files are misformatted, guess missing information
        if (imageSize==0)    imageSize=width*height*3; // 3 : one byte for each Red, Green and Blue component
        if (dataPos==0)      dataPos = 54; // The BMP header is done that way
        
        // Create a buffer
        data = new unsigned char [imageSize];
        
        // Read the actual data from the file into the buffer
        fread(data,1,imageSize,file);
        
        // Create one OpenGL texture
        GLuint textureID;
        glGenTextures(1, &textureID);
        
        // "Bind" the newly created texture : all future texture functions will modify this texture
        glBindTexture(GL_TEXTURE_2D, textureID);
        
        // Give the image to OpenGL
//        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, width, height, 0, GL_BGR, GL_UNSIGNED_BYTE, data);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, width, height, 0, GL_RGB, GL_UNSIGNED_BYTE, data);
        
        
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        
        //Everything is in memory now, the file can be closed
        fclose(file);
        delete []data;
        
        return textureID;
    }
    
    const char * const FaceBeautifyVideoFilter::vertexKernel() const
    {
        
        KERNEL(GL_ES2_3, m_language,
               attribute vec2 aPos;
               attribute vec2 aCoord;
               varying vec2   vCoord;
               uniform mat4   uMat;
               void main(void) {
                   gl_Position = uMat * vec4(aPos,0.,1.);
                   vCoord = aCoord;
               }
               )
        
        return nullptr;
    }
    
    const char * const FaceBeautifyVideoFilter::pixelKernel() const
    {
        
        KERNEL(GL_ES2_3, m_language,
               precision mediump float;
               varying vec2      vCoord;
               uniform sampler2D uTex0;
               
               uniform sampler2D uTex1;
               uniform sampler2D uTex2;
               uniform sampler2D uTex3;

               uniform float     uTime;
               
               void main(void) {
                   vec4 texel = texture2D(uTex0, vCoord);

                   float tt = mod(uTime, 100.0);
                   float brightness = ((tt + 150.0) / 300.0);

                   vec4 texel2 = texel;
                   texel2.r = texture2D(uTex3, vec2(texel.r, brightness)).r;
                   texel2.g = texture2D(uTex3, vec2(texel.g, brightness)).g;
                   texel2.b = texture2D(uTex3, vec2(texel.b, brightness)).b;
             
                   gl_FragColor = texel2;
               }
               )
        
        return nullptr;
    }

    void FaceBeautifyVideoFilter::initialize()
    {
        switch(m_language) {
            case GL_ES2_3:
            case GL_2: {
                setProgram(build_program(vertexKernel(), pixelKernel()));
                glGenVertexArrays(1, &m_vao);
                glBindVertexArray(m_vao);
                m_uMatrix = glGetUniformLocation(m_program, "uMat");
                
                m_uTime = glGetUniformLocation(m_program, "uTime");
                
                int attrpos = glGetAttribLocation(m_program, "aPos");
                int attrtex = glGetAttribLocation(m_program, "aCoord");
                int unitex = glGetUniformLocation(m_program, "uTex0");
                glUniform1i(unitex, 0);
                
                
                int unitex1 = glGetUniformLocation(m_program, "uTex1");
                
                NSBundle *mainBundle = [NSBundle mainBundle];
                NSString *imagePath1 = [mainBundle pathForResource:@"contrast_map" ofType:@"bmp"];
                NSLog(@"%@", imagePath1);
                
                GLuint textureID1 = loadBMP_custom(imagePath1.cString);
                glUniform1f(unitex1, textureID1);
                
                
                int unitex2 = glGetUniformLocation(m_program, "uTex2");

                NSString *imagePath2 = [mainBundle pathForResource:@"threshold_map" ofType:@"bmp"];
                NSLog(@"%@", imagePath2);
                
                GLuint textureID2 = loadBMP_custom(imagePath2.cString);
                glUniform1f(unitex2, textureID2);
                
                int unitex3 = glGetUniformLocation(m_program, "uTex3");
                
                NSString *imagePath3 = [mainBundle pathForResource:@"bright_map" ofType:@"bmp"];
                NSLog(@"%@", imagePath3);
                
                GLuint textureID3 = loadBMP_custom(imagePath3.cString);
                glUniform1f(unitex3, textureID3);
                
                
                glEnableVertexAttribArray(attrpos);
                glEnableVertexAttribArray(attrtex);
                glVertexAttribPointer(attrpos, BUFFER_SIZE_POSITION, GL_FLOAT, GL_FALSE, BUFFER_STRIDE, BUFFER_OFFSET_POSITION);
                glVertexAttribPointer(attrtex, BUFFER_SIZE_POSITION, GL_FLOAT, GL_FALSE, BUFFER_STRIDE, BUFFER_OFFSET_TEXTURE);
                m_initialized = true;
            }
                break;
            case GL_3:
                break;
        }
    }
    
    void FaceBeautifyVideoFilter::bind()
    {
        switch(m_language) {
            case GL_ES2_3:
            case GL_2:
                if(!m_bound) {
                    if(!initialized()) {
                        initialize();
                    }
                    glUseProgram(m_program);
                    glBindVertexArray(m_vao);
                }
                glUniformMatrix4fv(m_uMatrix, 1, GL_FALSE, &m_matrix[0][0]);
                
                glUniform1f(m_uTime, m_time);
                
                break;
            case GL_3:
                break;
        }
    }
    
    void FaceBeautifyVideoFilter::unbind()
    {
        m_bound = false;
    }

}
}