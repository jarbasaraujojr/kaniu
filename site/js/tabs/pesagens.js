export async function load(animalId) {
  const res = await fetch(`/api/animals/${animalId}/pesagens`);
  const data = await res.json();

  const container = document.getElementById("tab-pesagens");
  if (!data.length) {
    container.innerHTML = "<p>Nenhuma pesagem encontrada.</p>";
    return;
  }

  container.innerHTML = `
    <table class="tab-table">
      <thead>
        <tr><th>Data</th><th>Peso</th><th>Variação</th></tr>
      </thead>
      <tbody>
        ${data.map(p => `
          <tr>
            <td>${p.data}</td>
            <td>${p.peso} kg</td>
            <td>${p.variacao || "-"}</td>
          </tr>
        `).join("")}
      </tbody>
    </table>
    <div class="chart-container"><canvas id="weightChart"></canvas></div>
  `;

  renderChart(data);
}

function renderChart(data) {
  const ctx = document.getElementById("weightChart").getContext("2d");

  new Chart(ctx, {
    type: "line",
    data: {
      datasets: [{
        label: "Peso",
        data: data.map(p => ({ x: new Date(p.data), y: p.peso })),
        borderColor: "#4A90E2",
        backgroundColor: "rgba(74, 144, 226, 0.2)",
        fill: true,
        tension: 0.3,
        pointRadius: 3
      }]
    },
    options: {
      responsive: true,
      scales: {
        x: { type: "time", time: { unit: "month" } },
        y: { beginAtZero: true }
      },
      plugins: { legend: { display: false } }
    }
  });
}
