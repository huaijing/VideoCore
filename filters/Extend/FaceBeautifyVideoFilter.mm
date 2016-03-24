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
#import <OpenGLES/EAGL.h>
#import <OpenGLES/EAGLDrawable.h>

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
//        glDeleteTextures(1, &unitex1);
        
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
            printf("Not a correct BMP file");
            return false;
        }
        
        if ( header[0]!='B' || header[1]!='M' ){
            printf("Not a correct BMP file");
            return 0;
        }
        
        // Read ints from the byte array
        dataPos    = *(int*)&(header[0x0A]);
        imageSize  = *(int*)&(header[0x22]);
        width      = *(int*)&(header[0x12]);
        height     = *(int*)&(header[0x16]);
        
        // Some BMP files are misformatted, guess missing information
        if (imageSize == 0)    imageSize = width*height*3; // 3 : one byte for each Red, Green and Blue component
        if (dataPos == 0)      dataPos = 54; // The BMP header is done that way
        
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
               varying vec2   textureCoordinate;
               uniform mat4   uMat;
               void main(void) {
                   gl_Position = uMat * vec4(aPos,0.,1.);
                   textureCoordinate = aCoord;
               }
               )
        
        return nullptr;
    }
    
    const char * const FaceBeautifyVideoFilter::pixelKernel() const
    {
        
        KERNEL(GL_ES2_3, m_language,
               precision mediump float;
               
               varying vec2      textureCoordinate;
               
               uniform sampler2D inputImageTexture;
               uniform sampler2D inputImageTexture1;  //contrast
               uniform sampler2D inputImageTexture2;  //threshold
               uniform sampler2D inputImageTexture3;  //brightness

////               uniform lowp float contrast;
//               const float contrast = ((30.0 + 100.0) / 200.0);
//               
////               uniform highp float texelWidthOffset;
////               uniform highp float texelHeightOffset;
////               uniform highp float fStep;
//               const float texelWidthOffset = 1.0 / 320.0;
//               const float texelHeightOffset = 1.0 / 480.0;
//               const float fStep = 0.6 * 1.0;
//               
////               uniform lowp float brightness;
//               const float brightness = (255.0 - 160.0) / 3.0;
//               
//               uniform float     uTime;
//               
//               
//               vec2 getZoomPosition(float zoomTimes) {
//                   const float EPS = 0.0001;
//                   float zoom_x = (textureCoordinate.x - 0.5) / (zoomTimes + EPS);
//                   float zoom_y = (textureCoordinate.y - 0.5) / (zoomTimes + EPS);
//                   
//                   return vec2(0.5 + zoom_x, 0.5 + zoom_y);
//               }
//               
//               vec4 getColor(float zoomTimes) {
//                   vec2 pos = getZoomPosition(zoomTimes);
//                   
//                   float u = mod(pos.x, texelWidthOffset);
//                   float v = mod(pos.y, texelHeightOffset);
//                   
//                   float _x = pos.x - u;
//                   float _y = pos.y - v;
//                   
//                   vec4 data_00 = texture2D(inputImageTexture, vec2(_x, _y));
//                   vec4 data_01 = texture2D(inputImageTexture, vec2(_x, _y + texelHeightOffset));
//                   vec4 data_10 = texture2D(inputImageTexture, vec2(_x + texelWidthOffset, _y));
//                   vec4 data_11 = texture2D(inputImageTexture, vec2(_x + texelWidthOffset, _y + texelHeightOffset));
//                   
//                   return (1.0 - u) * (1.0 - v) * data_00 + (1.0 - u) * v * data_01 + u * (1.0 - v) * data_10 + u * v * data_11;
//               }
               
               void main()
               {
                   vec4 textureColor = texture2D(inputImageTexture3, textureCoordinate);

                   gl_FragColor = textureColor;
                   
                   
//                   highp vec4 texel;
//                   
//                   const float threshold0 = 100.0;
//                   const float threshold1 = 200.0;
//                   const float threshold2 = 300.0;
//                   if(uTime < threshold0)
//                   {
//                       float verticalThift = uTime / 100.0;
//                       float newY = verticalThift + textureCoordinate.y;
//                       if (newY <= 1.0) {
//                           texel = texture2D(inputImageTexture, vec2(textureCoordinate.x, newY));
//                       }
//                       else
//                       {
//                           texel = texture2D(inputImageTexture, vec2(textureCoordinate.x, newY - 1.0));
//                       }
//                   }
//                   else if(uTime < threshold1)
//                   {
//                       float horizontalThift = (uTime - 100.0) / 100.0;
//                       float newX = horizontalThift + textureCoordinate.x;
//                       if (newX <= 1.0) {
//                           texel = texture2D(inputImageTexture, vec2(newX, textureCoordinate.y));
//                       }
//                       else
//                       {
//                           texel = texture2D(inputImageTexture, vec2(newX - 1.0, textureCoordinate.y));
//                       }
//                   }
//                   else if(uTime < threshold2)
//                   {
//                       float zoomTimes = (uTime - 200.0) / 40.0;
//                       texel = getColor(zoomTimes);
//                   }
//                   else
//                   {
//                       texel = texture2D(inputImageTexture, textureCoordinate);
//                   }
//                   gl_FragColor = texel;
                   
                   
//                   vec4 textureColor = texture2D(inputImageTexture, textureCoordinate);
//                   
//                   vec4 texel = vec4(1.0);
//                   texel.r = texture2D(inputImageTexture2, vec2(textureColor.r, contrast)).r;
//                   texel.g = texture2D(inputImageTexture2, vec2(textureColor.g, contrast)).g;
//                   texel.b = texture2D(inputImageTexture2, vec2(textureColor.b, contrast)).b;
//                   
//                   
//                   lowp vec4 datatmp;
//                   highp vec4 sum = vec4(0.0);
//                   highp vec4 weightSum = vec4(1.0);
//                   highp vec4 weight;
//                   highp vec4 threshold = texture2D(inputImageTexture3, vec2(max(max(texel.r, texel.g), texel.b), 0.5));
//                   highp float Y = 2.5 * threshold.r + 0.0001;
//                   highp vec4 tt = vec4(1.0);
//                   
//                   datatmp = texture2D(inputImageTexture, textureCoordinate - vec2(-2.0 * fStep * texelWidthOffset, -2.0 * fStep * texelHeightOffset));
//                   weight = clamp(tt - abs(datatmp - texel) / Y, 0.0, 1.0);
//                   weightSum += weight;
//                   sum += weight * datatmp;
//                   
//                   datatmp = texture2D(inputImageTexture, textureCoordinate - vec2(-2.0 * fStep * texelWidthOffset, -1.0 * fStep * texelHeightOffset));
//                   weight = clamp(tt - abs(datatmp - texel) / Y, 0.0, 1.0);
//                   weightSum += weight;
//                   sum += weight * datatmp;
//                   
//                   datatmp = texture2D(inputImageTexture, textureCoordinate - vec2(-2.0 * fStep * texelWidthOffset, 0.0 * fStep * texelHeightOffset));
//                   weight = clamp(tt - abs(datatmp - texel) / Y, 0.0, 1.0);
//                   weightSum += weight;
//                   sum += weight * datatmp;
//                   
//                   datatmp = texture2D(inputImageTexture, textureCoordinate - vec2(-2.0 * fStep * texelWidthOffset, 1.0 * fStep * texelHeightOffset));
//                   weight = clamp(tt - abs(datatmp - texel) / Y, 0.0, 1.0);
//                   weightSum += weight;
//                   sum += weight * datatmp;
//                   
//                   datatmp = texture2D(inputImageTexture, textureCoordinate - vec2(-2.0 * fStep * texelWidthOffset, 2.0 * fStep * texelHeightOffset));
//                   weight = clamp(tt - abs(datatmp - texel) / Y, 0.0, 1.0);
//                   weightSum += weight;
//                   sum += weight * datatmp;
//                   
//                   datatmp = texture2D(inputImageTexture, textureCoordinate - vec2(-1.0 * fStep * texelWidthOffset, -2.0 * fStep * texelHeightOffset));
//                   weight = clamp(tt - abs(datatmp - texel) / Y, 0.0, 1.0);
//                   weightSum += weight;
//                   sum += weight * datatmp;
//                   
//                   datatmp = texture2D(inputImageTexture, textureCoordinate - vec2(-1.0 * fStep * texelWidthOffset, -1.0 * fStep * texelHeightOffset));
//                   weight = clamp(tt - abs(datatmp - texel) / Y, 0.0, 1.0);
//                   weightSum += weight;
//                   sum += weight * datatmp;
//                   
//                   datatmp = texture2D(inputImageTexture, textureCoordinate - vec2(-1.0 * fStep * texelWidthOffset, 0.0 * fStep * texelHeightOffset));
//                   weight = clamp(tt - abs(datatmp - texel) / Y, 0.0, 1.0);
//                   weightSum += weight;
//                   sum += weight * datatmp;
//                   
//                   datatmp = texture2D(inputImageTexture, textureCoordinate - vec2(-1.0 * fStep * texelWidthOffset, 1.0 * fStep * texelHeightOffset));
//                   weight = clamp(tt - abs(datatmp - texel) / Y, 0.0, 1.0);
//                   weightSum += weight;
//                   sum += weight * datatmp;
//                   
//                   datatmp = texture2D(inputImageTexture, textureCoordinate - vec2(-1.0 * fStep * texelWidthOffset, 2.0 * fStep * texelHeightOffset));
//                   weight = clamp(tt - abs(datatmp - texel) / Y, 0.0, 1.0);
//                   weightSum += weight;
//                   sum += weight * datatmp;
//                   
//                   datatmp = texture2D(inputImageTexture, textureCoordinate - vec2(0.0 * fStep * texelWidthOffset, -2.0 * fStep * texelHeightOffset));
//                   weight = clamp(tt - abs(datatmp - texel) / Y, 0.0, 1.0);
//                   weightSum += weight;
//                   sum += weight * datatmp;
//                   
//                   datatmp = texture2D(inputImageTexture, textureCoordinate - vec2(0.0 * fStep * texelWidthOffset, -1.0 * fStep * texelHeightOffset));
//                   weight = clamp(tt - abs(datatmp - texel) / Y, 0.0, 1.0);
//                   weightSum += weight;
//                   sum += weight * datatmp;
//                   
//                   datatmp = texture2D(inputImageTexture, textureCoordinate - vec2(0.0 * fStep * texelWidthOffset, 0.0 * fStep * texelHeightOffset));
//                   weight = clamp(tt - abs(datatmp - texel) / Y, 0.0, 1.0);
//                   weightSum += weight;
//                   sum += weight * datatmp;
//                   
//                   datatmp = texture2D(inputImageTexture, textureCoordinate - vec2(0.0 * fStep * texelWidthOffset, 1.0 * fStep * texelHeightOffset));
//                   weight = clamp(tt - abs(datatmp - texel) / Y, 0.0, 1.0);
//                   weightSum += weight;
//                   sum += weight * datatmp;
//                   
//                   datatmp = texture2D(inputImageTexture, textureCoordinate - vec2(0.0 * fStep * texelWidthOffset, 2.0 * fStep * texelHeightOffset));
//                   weight = clamp(tt - abs(datatmp - texel) / Y, 0.0, 1.0);
//                   weightSum += weight;
//                   sum += weight * datatmp;
//                   
//                   datatmp = texture2D(inputImageTexture, textureCoordinate - vec2(1.0 * fStep * texelWidthOffset, -2.0 * fStep * texelHeightOffset));
//                   weight = clamp(tt - abs(datatmp - texel) / Y, 0.0, 1.0);
//                   weightSum += weight;
//                   sum += weight * datatmp;
//                   
//                   datatmp = texture2D(inputImageTexture, textureCoordinate - vec2(1.0 * fStep * texelWidthOffset, -1.0 * fStep * texelHeightOffset));
//                   weight = clamp(tt - abs(datatmp - texel) / Y, 0.0, 1.0);
//                   weightSum += weight;
//                   sum += weight * datatmp;
//                   
//                   datatmp = texture2D(inputImageTexture, textureCoordinate - vec2(1.0 * fStep * texelWidthOffset, 0.0 * fStep * texelHeightOffset));
//                   weight = clamp(tt - abs(datatmp - texel) / Y, 0.0, 1.0);
//                   weightSum += weight;
//                   sum += weight * datatmp;
//                   
//                   datatmp = texture2D(inputImageTexture, textureCoordinate - vec2(1.0 * fStep * texelWidthOffset, 1.0 * fStep * texelHeightOffset));
//                   weight = clamp(tt - abs(datatmp - texel) / Y, 0.0, 1.0);
//                   weightSum += weight;
//                   sum += weight * datatmp;
//                   
//                   datatmp = texture2D(inputImageTexture, textureCoordinate - vec2(1.0 * fStep * texelWidthOffset, 2.0 * fStep * texelHeightOffset));
//                   weight = clamp(tt - abs(datatmp - texel) / Y, 0.0, 1.0);
//                   weightSum += weight;
//                   sum += weight * datatmp;
//                   
//                   datatmp = texture2D(inputImageTexture, textureCoordinate - vec2(2.0 * fStep * texelWidthOffset, -2.0 * fStep * texelHeightOffset));
//                   weight = clamp(tt - abs(datatmp - texel) / Y, 0.0, 1.0);
//                   weightSum += weight;
//                   sum += weight * datatmp;
//                   
//                   datatmp = texture2D(inputImageTexture, textureCoordinate - vec2(2.0 * fStep * texelWidthOffset, -1.0 * fStep * texelHeightOffset));
//                   weight = clamp(tt - abs(datatmp - texel) / Y, 0.0, 1.0);
//                   weightSum += weight;
//                   sum += weight * datatmp;
//                   
//                   datatmp = texture2D(inputImageTexture, textureCoordinate - vec2(2.0 * fStep * texelWidthOffset, 0.0 * fStep * texelHeightOffset));
//                   weight = clamp(tt - abs(datatmp - texel) / Y, 0.0, 1.0);
//                   weightSum += weight;
//                   sum += weight * datatmp;
//                   
//                   datatmp = texture2D(inputImageTexture, textureCoordinate - vec2(2.0 * fStep * texelWidthOffset, 1.0 * fStep * texelHeightOffset));
//                   weight = clamp(tt - abs(datatmp - texel) / Y, 0.0, 1.0);
//                   weightSum += weight;
//                   sum += weight * datatmp;
//                   
//                   datatmp = texture2D(inputImageTexture, textureCoordinate - vec2(2.0 * fStep * texelWidthOffset, 2.0 * fStep * texelHeightOffset));
//                   weight = clamp(tt - abs(datatmp - texel) / Y, 0.0, 1.0);
//                   weightSum += weight;
//                   sum += weight * datatmp;
//                   
//                   sum = clamp(sum / (weightSum + 0.0001), 0.0, 1.0);
//                   vec4 texel2 = texel;
//                   if(texel.r >= 0.25 && texel.g >= 0.25 && texel.b >= 0.25)
//                   {
//                       texel2.rgb = sum.rgb;
//                   }
//                   
//                   
//                   vec4 texel3 = vec4(1.0);
//                   texel3.r = texture2D(inputImageTexture4, vec2(texel2.r, brightness)).r;
//                   texel3.g = texture2D(inputImageTexture4, vec2(texel2.g, brightness)).g;
//                   texel3.b = texture2D(inputImageTexture4, vec2(texel2.b, brightness)).b;
//                   
//                   gl_FragColor = texel3;
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
                
//                GLuint unitex = glGetUniformLocation(m_program, "inputImageTexture");
//                glUniform1i(unitex, 0);
                
                NSBundle *mainBundle = [NSBundle mainBundle];
                
                NSString *imagePath1 = [mainBundle pathForResource:@"contrast_map" ofType:@"bmp"];
                m_texture = loadBMP_custom(imagePath1.cString);
                glActiveTexture(GL_TEXTURE2);
                glBindTexture(GL_TEXTURE_2D, m_texture);
                NSLog(@"%@， %u", imagePath1, m_texture);
           
                
                NSString *imagePath2 = [mainBundle pathForResource:@"threshold_map" ofType:@"bmp"];
                m_texture2 = loadBMP_custom(imagePath2.cString);
                glActiveTexture(GL_TEXTURE3);
                glBindTexture(GL_TEXTURE_2D, m_texture2);
                NSLog(@"%@， %u", imagePath2, m_texture2);

                
                NSString *imagePath3 = [mainBundle pathForResource:@"bright_map" ofType:@"bmp"];
                m_texture3 = loadBMP_custom(imagePath3.cString);
                glActiveTexture(GL_TEXTURE4);
                glBindTexture(GL_TEXTURE_2D, m_texture3);
                NSLog(@"%@， %u", imagePath3, m_texture3);

//                glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

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
                    
                    GLuint unitex1 = glGetUniformLocation(m_program, "inputImageTexture1");
                    glActiveTexture(GL_TEXTURE2);
                    glBindTexture(GL_TEXTURE_2D, m_texture);
                    glUniform1f(unitex1, 2);
                    
                    GLuint unitex2 = glGetUniformLocation(m_program, "inputImageTexture2");
                    glActiveTexture(GL_TEXTURE3);
                    glBindTexture(GL_TEXTURE_2D, m_texture2);
                    glUniform1f(unitex2, 3);
                    
                    GLuint unitex3 = glGetUniformLocation(m_program, "inputImageTexture3");
                    glActiveTexture(GL_TEXTURE4);
                    glBindTexture(GL_TEXTURE_2D, m_texture3);
                    glUniform1f(unitex3, 4);
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