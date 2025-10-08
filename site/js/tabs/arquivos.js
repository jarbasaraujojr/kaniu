export async function load(animalId) {
  const res = await fetch(`/api/animals/${animalId}/arquivos`);
  const data = await res.json();

  const container = document.getElementById("tab-arquivos");
  if (!data.length) {
    container.innerHTML = "<p>Nenhum arquivo disponível.</p>";
    return;
  }

  container.innerHTML = `
    <table class="tab-table">
      <thead>
        <tr><th>Data</th><th>Nome</th><th>Observação</th><th>Ação</th></tr>
      </thead>
      <tbody>
        ${data.map(arq => `
          <tr>
            <td>${arq.data}</td>
            <td>${arq.nome}</td>
            <td>${arq.observacao || "-"}</td>
            <td><a href="${arq.url}" target="_blank">Visualizar</a></td>
          </tr>
        `).join("")}
      </tbody>
    </table>
  `;
}
