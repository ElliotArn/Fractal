#include "raylib.h"
#include <cuda_runtime.h>
#include <device_launch_parameters.h>
#include <stdio.h>


/* 
    Width of the screen
    Height of the screen, height also determines the amount of threads th use on the gpu
    Amount of blocks on the gpu to use
    Complexre is the real part of the complex number the Mandelbrot set is based on
    Complexim is the complex part of the complex number the Mandelbrot set is based on
 */
#define WIDTH  1900
#define HEIGHT 1024
#define AMOUNT 100
#define COMPLEXRE -0.4
#define COMPLEXIM 0.6


#if HEIGHT > 1024
    #error "Height is too big for the number of threads!"
#endif

// CUDA kernel to iterate through the Mandelbrot set on GPU
__global__ void iterategpu(double* imagine, double* real, unsigned char* C, int index){
    unsigned char i = 0;
    int thread = threadIdx.x;
    int block = blockIdx.x;
    double re = real[(index * AMOUNT + block) * HEIGHT + thread];
    double im = imagine[(index * AMOUNT + block) * HEIGHT + thread];

    // Iterate through the Mandelbrot set
    while (re * re + im * im < 2.0 && i < 200) {
        i++;
        double temp = re * re - im * im + COMPLEXRE;
        im = 2.0 * re * im + COMPLEXIM;
        re = temp;
    }

    // Store the iteration count in the output array
    C[(index * AMOUNT + block) * HEIGHT + thread] = i;
}

// Arrays for GPU computations
unsigned char screen[WIDTH * HEIGHT];
double inputIm[WIDTH * HEIGHT];
double inputRe[WIDTH * HEIGHT];


// Function to render the Mandelbrot set on GPU
void render(int offsetX, int offsetY, double zoom, double* inRe, double* inIm, unsigned char* out) {
    // Generate Mandelbrot set coordinates
    for (int i = 0; i < WIDTH; i++) {
        for (int j = 0; j < HEIGHT; j++) {
            double re = (double)(offsetX + i - (WIDTH / 2)) * zoom;
            double im = (double)(offsetY + j - (HEIGHT / 2)) * zoom;

            inputRe[i * HEIGHT + j] = re;
            inputIm[i * HEIGHT + j] = im;
        }
    }

    // Copy Mandelbrot set coordinates to GPU
    cudaMemcpy(inRe, inputRe, sizeof(inputRe), cudaMemcpyHostToDevice);
    cudaMemcpy(inIm, inputIm, sizeof(inputIm), cudaMemcpyHostToDevice);

    // Launch GPU kernel for Mandelbrot set computation
    for (int i = 0; i < WIDTH / AMOUNT; i++) {
        iterategpu <<<AMOUNT, HEIGHT>>> (inRe, inIm, out, i);
        cudaDeviceSynchronize();
    }

    // Copy the result back to the CPU
    cudaMemcpy(screen, out, sizeof(screen), cudaMemcpyDeviceToHost);
}

// Function to draw the Mandelbrot set using raylib
void draw(int x, int y, double zoom, double* inRe, double* inIm, unsigned char* out) {
    BeginDrawing();
    unsigned char colorvalue;

    // Render the Mandelbrot set on GPU and copy it to the CPU
    render(x, y, zoom, inRe, inIm, out);

    // Draw the fractal in raylib
    for (int i = 0; i < WIDTH; i++) {
        for (int j = 0; j < HEIGHT; j++) {
            colorvalue = screen[i * HEIGHT + j];
            Color color = (Color){colorvalue, 0, (unsigned char)(2*colorvalue), 255};
            DrawPixel(i, j, color);
        }
    }

    EndDrawing();
}

int main() {
    double zoom = 4 / (double)HEIGHT;
    int x = 0;
    int y = 0;

    // Pointers to the VRAM
    double* inRe = 0;
    double* inIm = 0;
    unsigned char* out = 0;

    // Allocate memory on GPU
    cudaMalloc(&inIm, sizeof(inputIm));
    cudaMalloc(&inRe, sizeof(inputRe));
    cudaMalloc(&out, sizeof(screen));

    // Initialize raylib window
    InitWindow(WIDTH, HEIGHT, "Fractal");
    SetTargetFPS(20);
    draw(x, y, zoom, inRe, inIm, out);

    // Main loop
    while (!WindowShouldClose()) {
        // Handle mouse input to zoom and pan the Mandelbrot set
        if (IsMouseButtonPressed(MOUSE_BUTTON_LEFT)) {
            Vector2 mousePosition = GetMousePosition();
            zoom *= 0.9;
            mousePosition.x -= WIDTH / 2;
            mousePosition.y -= HEIGHT / 2;

            mousePosition.x *= 0.0004 / zoom;
            mousePosition.y *= 0.0004 / zoom;

            x += mousePosition.x;
            y += mousePosition.y;

            draw(x, y, zoom, inRe, inIm, out);
        }
        // left mouse button zooms out
        else if (IsMouseButtonPressed(MOUSE_BUTTON_RIGHT)) {
            zoom *= 1.1;
            draw(x, y, zoom, inRe, inIm, out);
        }

        BeginDrawing();
        // The following line is required for raylib
        EndDrawing();
    }

    // Close raylib window
    CloseWindow();

    // Free memory on GPU
    cudaFree(inIm);
    cudaFree(inRe);
    cudaFree(out);

    return 0;
}
