# NeuroFlow: Normative Brain Dynamics & Three-Way Interactions

NeuroFlow is an advanced mathematical analysis pipeline and interactive web dashboard designed to model normative cohort functional connectivity and high-order nonlinear dynamics (3-way network interactions). 

The platform is designed to run locally using MATLAB and Python, and deploys as a fully standalone web application that requires no backend services.

---

## 🚀 Interactive Dashboard Preview

When hosted on GitHub Pages, the interactive dashboard is served directly to users. 

### Key Dashboard Features:
1. **Multi-Cohort Navigation**: Seamless switching between the **HCP Cohort** (9 tasks) and **IMAGEN Cohort** (2 tasks).
2. **Wasserstein Barycenter**: View bootstrap-corrected consensus correlation structures.
3. **Wasserstein PGA**: Explore principal geodesic components, scree variance, and geodesic reconstructions ($-2\sigma$ to $+2\sigma$).
4. **3-Way Interactions**: Analyze symmetric CP tensor components (singular values and explained non-Gaussian variance) and search/filter ranks of top general and cross-network triad modulations ($M_{abc}$).
5. **Interactive Methodology Tab**: A mathematical reference sheet showing the pipeline steps, rendered dynamically in-browser via MathJax.

---

## 🛠️ The Pipeline Architecture

The underlying analysis pipeline is written in MATLAB and implements the following steps:

1. **Spatial Network Averaging**: Dimension reduction of 268 brain nodes into 10 canonical networks.
2. **Individual Functional Connectivity**: Subject-level Pearson correlation matrices.
3. **Bures-Wasserstein Fréchet Mean**: Cohort consensus covariance calculated on the PSD manifold using Alvarez-Esteban fixed-point iterations.
4. **Principal Geodesic Analysis (PGA)**: Tangent-space projection, metric-preserving vectorization (scaling off-diagonals by $\sqrt{2}$), bootstrap-thresholded sparse loadings, and exponential-map reconstruction.
5. **Symmetric CP Tensor Decomposition**: Alternating Least Squares (ALS) to extract 5 spatial-mode component matrices and cohort expressions.
6. **Precision-Matrix Contraction (Adjusted Triad Index $M_{abc}$)**: Projecting joint third-order moments through the covariance geometry to remove lower-order linear Gaussian dependencies, leaving pure non-linear modulations.

---

## ⚙️ Running Locally

### 1. Execute the MATLAB Pipeline
Run the main pipeline script in MATLAB to compute barycenters, PGAs, symmetric CP decompositions, and triad indices for all tasks:
```matlab
run_normative_pipeline
```
This writes task outputs, reports, and `.csv` files to the `outputs/` directory.

### 2. Compile Data for Web Dashboard
Run the Python data scraper to ingest reports and plots and package them into a single local JSON script:
```bash
python web/prepare_web_data.py
```

### 3. Open the Dashboard
Simply double-click `web/index.html` to view the interactive dashboard in your web browser. Due to a synchronous JSON data-injector, it runs entirely offline and standalone without CORS warnings.

---

## 📦 Deployment to GitHub Pages

This repository is equipped with a GitHub Actions workflow that automatically deploys the `web` subdirectory to the `gh-pages` branch upon pushing to `main`. 

See the instructions in the repository description to configure it.
