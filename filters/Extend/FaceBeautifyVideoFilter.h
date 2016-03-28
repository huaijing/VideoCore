//
//  FaceBeautifyVideoFilter.h
//  Pods
//
//  Created by jing huai on 16/3/18.
//
//

#ifndef FaceBeautifyVideoFilter_h
#define FaceBeautifyVideoFilter_h
#include <videocore/filters/IVideoFilter.hpp>

namespace videocore {
    namespace filters {
        class FaceBeautifyVideoFilter : public IVideoFilter {
        
        public:
            FaceBeautifyVideoFilter();
            ~FaceBeautifyVideoFilter();
            
        public:
            virtual void initialize();
            virtual bool initialized() const { return m_initialized; };
            virtual std::string const name() { return "com.videocore.filters.faceBeautify"; };
            virtual void bind();
            virtual void unbind();
            
        public:
            
            const char * const vertexKernel() const ;
            const char * const pixelKernel() const ;
            
        private:
            static bool registerFilter();
            static bool s_registered;
            
        private:
            unsigned int m_vao;
            unsigned int m_uMatrix;
            bool m_initialized;
            bool m_bound;
        
//        private:
//            virtual int loadBMP_custom(const char * imagepath);
        
//        private:
//            unsigned int m_uTime;
        };
    }
}

#endif /* FaceBeautifyVideoFilter_h */
